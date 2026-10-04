# Technical Test – Shift Engineer DevOps (PT Simple Journey Indonesia)

Go HTTP server → Docker (multi-stage, static binary, image `scratch`) → hot-swap binary tanpa rebuild image → pipeline Jenkins → infrastruktur AWS via Terraform.

- **Go version:** 1.22 (builder `golang:1.22-alpine`; host Jenkins memakai Go 1.22.10)
- **Panduan setup langkah demi langkah (AWS → Terraform → Jenkins → deploy):** [`docs/SETUP-GUIDE.md`](docs/SETUP-GUIDE.md)
- **Troubleshooting:** [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

## Struktur repo

```
.
├── app/                         # Website / aplikasi Go
│   ├── main.go, main_test.go, go.mod
│   ├── Dockerfile, .dockerignore
│   └── scripts/
│       ├── build.sh             # docker build dengan versi
│       ├── run.sh               # docker run (port 8080, --restart, mount binary)
│       ├── hotfix-swap.sh       # ganti binary + restart + health check + auto-rollback
│       └── demo-swap.sh         # demo Part I & II end-to-end (bukti before/after)
├── cicd/
│   ├── Jenkinsfile              # Checkout → Test → Build → Push → Deploy → Verify
│   └── scripts/deploy.sh        # dipanggil stage Deploy (scp + hot-swap via SSH)
├── infra/
│   ├── terraform/               # VPC, SG, key pair, 2x EC2 (Jenkins & App), EIP
│   └── scripts/                 # user-data: install Docker, Go, Java, Jenkins otomatis
└── docs/                        # SETUP-GUIDE.md, TROUBLESHOOTING.md
```

## Arsitektur

```
 Developer ──push──▶ GitHub
                        │ (checkout)
                        ▼
              ┌───────────────────┐   ssh/scp (key dari Jenkins credentials)   ┌────────────────────┐
              │ EC2 Jenkins       │ ─────────────────────────────────────────▶ │ EC2 App            │
              │ Docker, Go, JDK17 │   hot-swap binary + docker restart         │ Docker             │
              │ Jenkins :8080     │                                            │ container :8080    │
              └───────────────────┘                                            └────────────────────┘
                 VPC 10.20.0.0/16, public subnet, Elastic IP, SG dibatasi ke IP admin
```

## Quick start

### A. Lokal (butuh Docker saja, Go tidak perlu)

```bash
cd app
./scripts/demo-swap.sh        # build v1.0.0 → run → curl → swap ke v1.0.1 → curl → ukur downtime
```

Atau manual:

```bash
cd app
docker build --build-arg VERSION=1.0.0 -t hello-devops:1.0.0 .
docker images hello-devops
BIN_DIR=$PWD/.demo/bin IMAGE=hello-devops:1.0.0 ./scripts/run.sh
curl localhost:8080/          # Hello, DevOps! version=1.0.0
```

### B. AWS (Terraform)

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars    # isi allowed_admin_cidrs dengan IP Anda
terraform init && terraform apply
```

Lalu ikuti `docs/SETUP-GUIDE.md` bagian Jenkins (unlock, credential, buat job, Build Now).

---

## Part I – Build

**Dockerfile:** [`app/Dockerfile`](app/Dockerfile)

**Build command:**

```bash
docker build --build-arg VERSION=1.0.0 -t hello-devops:1.0.0 app/
```

**Memenuhi syarat:**

| Syarat | Implementasi |
|---|---|
| Static binary | `CGO_ENABLED=0` + `-trimpath` → tidak ada ketergantungan libc/shared library |
| Versi saat build | `-ldflags="-s -w -X main.version=${VERSION}"` dari `--build-arg VERSION` |
| Tanpa Go di host | Compile terjadi di stage `builder`; image akhir hanya berisi binary |
| Non-root | `USER 65534:65534` |

**Pilihan base image final: `scratch`.** Binary Go yang static tidak butuh libc, shell, maupun package manager, jadi `scratch` memberi ukuran terkecil dan attack surface paling kecil (tidak ada shell, tidak ada OS package yang bisa punya CVE). Trade-off: tidak ada shell untuk `docker exec` debugging dan tidak ada CA bundle/timezone (tidak dibutuhkan app ini). Karena itu health check dibuat sebagai flag di binary (`-healthcheck`), bukan `curl`. Jika nanti perlu debugging/TLS keluar, alternatifnya `distroless/static` (≈2 MB tambahan, ada CA certs & user nonroot).

**Ukuran image final:** biasanya **±4–6 MB** (`docker images hello-devops`). Ukuran itu hampir seluruhnya adalah satu file binary Go (runtime Go + `net/http`), dikecilkan oleh `-s -w` (tanpa symbol/debug info). Tidak ada layer OS karena base-nya `scratch`.
Bandingkan: image `golang:1.22-alpine` ±250 MB, `alpine` ±8 MB + binary.

> 📌 Tempel output asli Anda di sini setelah menjalankan:
> ```
> $ docker images hello-devops
> REPOSITORY     TAG     IMAGE ID   CREATED   SIZE
> hello-devops   1.0.0   <id>       <...>     <...MB>
> ```

Verifikasi binary static:

```bash
cid=$(docker create hello-devops:1.0.0) && docker cp $cid:/app/bin/server /tmp/server && docker rm $cid
ldd /tmp/server        # → "not a dynamic executable"
file /tmp/server       # → "statically linked"
```

## Part II – Deploy

**Menjalankan container (port 8080 + restart policy):**

```bash
docker run -d --name hello-devops \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /opt/hello-devops/bin:/app/bin:ro \
  hello-devops:1.0.0
```

`--restart unless-stopped`: container otomatis dihidupkan lagi saat crash (exit ≠ 0 / proses mati) dan saat Docker daemon/host reboot, kecuali dihentikan manual (`docker stop`). Script: [`app/scripts/run.sh`](app/scripts/run.sh).

**Pendekatan yang dipilih: bind-mount direktori binary dari host (opsi 2).**
Image berisi binary di `/app/bin/server`, tetapi direktori `/app/bin` ditimpa (mount read-only) oleh `/opt/hello-devops/bin` di host. Hotfix = ganti file `server` di host (rename atomik) lalu `docker restart`. Script: [`app/scripts/hotfix-swap.sh`](app/scripts/hotfix-swap.sh).

**Semua perintah hotfix:**

```bash
# 1. Build binary baru TANPA docker build image (container Go sementara)
docker run --rm -v "$PWD":/src -w /src -e CGO_ENABLED=0 golang:1.22-alpine \
  go build -trimpath -ldflags="-s -w -X main.version=1.0.1" -o dist/server-1.0.1 .

# 2. Swap + restart + health check + rollback otomatis bila gagal
./scripts/hotfix-swap.sh dist/server-1.0.1 1.0.1
#   (di dalamnya: cp server → .server.previous ; install → .server.new ; mv -f .server.new server ;
#    docker restart -t 5 hello-devops ; curl health check)
```

**Bukti before/after** (jalankan `app/scripts/demo-swap.sh`, tempel hasil Anda):

```
### BEFORE swap
Hello, DevOps! version=1.0.0
### AFTER swap
Hello, DevOps! version=1.0.1
Container ID : <sama>     Image ID : <sama>     # container tidak dibuat ulang, image tidak di-build ulang
Waktu restart sampai sehat: ~1000-2000 ms
```

**Penjelasan (kenapa cocok untuk hotfix produksi):** Dengan mount direktori, image tetap immutable dan container yang sama hanya di-restart, sehingga downtime hanya ±1–2 detik (stop graceful + start proses baru) tanpa menunggu `docker build`/pull ulang. Direktori yang di-mount (bukan file tunggal) dipilih agar rename atomik (`mv`) tidak membuat bind-mount menunjuk inode lama. Binary lama selalu disimpan (`.server.previous`) sehingga rollback hanya satu `mv` + restart, dan script otomatis rollback bila health check gagal. Kekurangannya: binary di host menjadi "drift" dari isi image — karena itu pipeline CI/CD tetap membangun image bertag versi/commit sebagai sumber binary, jadi image dan binary yang berjalan selalu sama dan traceable.

**Opsi lain & trade-off:** (a) `docker cp` + restart: sederhana, tapi perubahan hilang jika container dibuat ulang dan tidak survive `docker rm`. (b) Sidecar/init container + shared volume: lebih "Kubernetes-native" dan bisa diaudit, tapi lebih kompleks untuk single-host.

## Part III – CI/CD Jenkins

**Jenkinsfile:** [`cicd/Jenkinsfile`](cicd/Jenkinsfile) · **Deploy script:** [`cicd/scripts/deploy.sh`](cicd/scripts/deploy.sh)

| Stage | Isi |
|---|---|
| Checkout | `checkout scm`, hitung versi `1.0.<build>-<git short sha>` |
| Test | `go vet` + `go test -v ./...` — gagal = pipeline berhenti, tidak lanjut build/deploy |
| Build Image | `docker build --build-arg VERSION=<versi> -t hello-devops:<versi>` |
| Push *(opsional)* | `PUSH_IMAGE=true` → `docker login` dengan credential `registry-credentials` (Docker Hub / ECR / GHCR) |
| Deploy | Ekstrak binary dari image → `scp` ke app server → `hotfix-swap.sh` via SSH |
| Verify | `curl` dari Jenkins, pastikan response memuat versi baru |

**Credentials (tidak ada secret di Jenkinsfile):** `app-server-ssh` (SSH Username with private key, user `ubuntu`) dan `registry-credentials` (Username with password, hanya bila push), dipakai lewat `withCredentials`. IP app server diberikan Terraform sebagai env global `APP_SERVER_HOST`.

> 📌 Tempel screenshot/log pipeline hijau Anda di `docs/screenshots/` dan tautkan di sini.

**Rollback bila deploy gagal di tengah jalan:**
1. Binary lama selalu dicadangkan ke `.server.previous` **sebelum** diganti; penggantian memakai rename atomik sehingga tidak pernah ada binary setengah-tertulis.
2. Setelah `docker restart`, `hotfix-swap.sh` melakukan health check (maks 20 detik) yang mengharuskan versi baru terdeteksi. Jika gagal, script otomatis mengembalikan binary lama, restart lagi, dan keluar dengan kode 1 → stage Deploy **merah** dan Jenkins menandai build FAILED, sementara layanan tetap berjalan di versi lama.
3. Jika koneksi SSH/scp putus sebelum swap, container belum disentuh sama sekali (tidak ada perubahan). Rollback manual: `mv .server.previous server && docker restart hello-devops`, atau jalankan ulang build lama dari Jenkins (binary tiap versi tersimpan di `/opt/hello-devops/releases`, 5 terakhir).

## Catatan keamanan

- SSH & Jenkins UI hanya terbuka untuk IP di `allowed_admin_cidrs`. Untuk produksi tambahkan HTTPS (ALB/ACM atau Nginx + Let's Encrypt).
- Private key dibuat Terraform dan tersimpan di `infra/terraform/generated/` serta **state Terraform** — pakai remote state terenkripsi (S3 + DynamoDB lock) untuk tim.
- Jangan commit `*.pem`, `terraform.tfvars`, `*.tfstate` (sudah di `.gitignore`).
