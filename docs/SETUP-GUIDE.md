# Panduan Setup Lengkap

Total waktu ±30–40 menit. Biaya AWS kasar: t3.medium + t3.micro + 2 EIP ≈ US$1/hari — **jalankan `terraform destroy` setelah selesai**.

## 0. Prasyarat di laptop Anda

| Tool | Cek |
|---|---|
| Git | `git --version` |
| Terraform ≥ 1.5 | `terraform version` (https://developer.hashicorp.com/terraform/install) |
| AWS CLI v2 | `aws --version` |
| Docker (untuk demo lokal) | `docker --version` |
| Akun AWS + IAM user | permission: EC2, VPC (cukup `AmazonEC2FullAccess` + `AmazonVPCFullAccess` untuk uji coba) |

## 1. Siapkan credential AWS

```bash
aws configure          # isi Access Key, Secret, region ap-southeast-1, output json
aws sts get-caller-identity    # harus menampilkan akun Anda
```

## 2. Siapkan repo GitHub

```bash
git init && git add . && git commit -m "Initial commit: DevOps technical test"
git branch -M main
git remote add origin https://github.com/<user>/<repo>.git
git push -u origin main
```

Invite `admin@simplejourney.co.id` sebagai collaborator: **Settings → Collaborators → Add people**. Kirim link repo setelah invite terkirim.

## 3. (Opsional) Uji lokal dulu

```bash
cd app && ./scripts/demo-swap.sh
```
Simpan outputnya sebagai bukti Part I & II (ukuran image, curl before/after, container ID & image ID tidak berubah).

## 4. Buat infrastruktur AWS dengan Terraform

```bash
cd infra/terraform
curl -s https://checkip.amazonaws.com            # catat IP publik Anda
cp terraform.tfvars.example terraform.tfvars
# edit: allowed_admin_cidrs = ["<IP-ANDA>/32"]
terraform init
terraform validate
terraform plan
terraform apply            # ketik yes
```

Yang dibuat: VPC, subnet publik, IGW, route table, 2 security group, key pair (`generated/hello-devops.pem`), EC2 app, EC2 Jenkins, 2 Elastic IP. Catat output (`terraform output`).

## 5. Tunggu bootstrap selesai (±5–8 menit)

User-data otomatis menginstal tools. Pantau:

```bash
# Jenkins server
ssh -i generated/hello-devops.pem ubuntu@<JENKINS_IP> 'tail -f /var/log/bootstrap.log'
# selesai bila muncul "BOOTSTRAP SELESAI" atau file /var/lib/bootstrap.done ada
```

Verifikasi tools:

```bash
# Jenkins server
ssh -i generated/hello-devops.pem ubuntu@<JENKINS_IP> \
  'docker --version; go version; java -version 2>&1 | head -1; systemctl is-active jenkins; id jenkins'
# App server
ssh -i generated/hello-devops.pem ubuntu@<APP_IP> 'docker --version; systemctl is-active docker; ls -ld /opt/hello-devops'
```

| Server | Terpasang otomatis |
|---|---|
| Jenkins | Docker CE, Go 1.22.10, OpenJDK 17, Jenkins LTS (systemd, user `jenkins` di grup `docker`), git, curl, jq, openssh-client |
| App | Docker CE, direktori `/opt/hello-devops/{bin,releases,scripts}` milik user `ubuntu` |

## 6. Setup Jenkins

1. Ambil password awal: jalankan perintah di output `get_jenkins_password`.
2. Buka `jenkins_url` (http://\<JENKINS_IP\>:8080) → paste password → **Install suggested plugins** → buat admin user.
3. **Manage Jenkins → Credentials → System → Global → Add Credentials**
   - Kind **SSH Username with private key**, ID `app-server-ssh`, Username `ubuntu`, Private Key → *Enter directly* → isi dengan `cat infra/terraform/generated/hello-devops.pem`.
   - *(Opsional push)* Kind **Username with password**, ID `registry-credentials` (Docker Hub user + access token).
4. Cek env global: **Manage Jenkins → System → Global properties → Environment variables** harus ada `APP_SERVER_HOST` (diisi otomatis; jika kosong isi IP private app = output `app_private_ip`, atau isi parameter `APP_HOST` saat build).
5. **New Item** → nama `hello-devops` → **Pipeline** → OK.
   - Definition: *Pipeline script from SCM* → SCM *Git* → Repository URL repo Anda (repo private: tambahkan credential GitHub token).
   - Branch `*/main`, **Script Path: `cicd/Jenkinsfile`** → Save.
6. **Build Now** (build pertama membuat parameter; build kedua dst. gunakan *Build with Parameters*).

## 7. Verifikasi hasil

```bash
curl http://<APP_IP>:8080/        # Hello, DevOps! version=1.0.<build>-<sha>
```

Ambil screenshot Stage View (semua hijau) + Console Output → simpan di `docs/screenshots/`.

## 8. Demo hotfix lewat pipeline

1. Ubah teks di `app/main.go` (mis. tambah kata), commit & push.
2. **Build Now** lagi. Pipeline: test → build → upload binary → `docker restart` (container ID sama, downtime ±1–2 detik) → Verify.
3. `curl` lagi: versi berubah. Cek di app server: `docker ps`, `ls /opt/hello-devops/releases`.

Demo test gagal: ubah string di `main_test.go` agar salah → push → stage Test merah, Build/Deploy **tidak berjalan**. Kembalikan setelah demo.

Demo rollback: di app server, deploy binary yang sengaja rusak (mis. `printf '#!/bin/sh\nexit 1' > /tmp/bad && /opt/hello-devops/scripts/hotfix-swap.sh /tmp/bad`) → health check gagal → script rollback otomatis, layanan kembali ke versi lama.

## 9. Bersihkan

```bash
cd infra/terraform && terraform destroy
```

## Menjalankan script bootstrap manual (tanpa Terraform)

Di Ubuntu 22.04 baru:

```bash
sudo bash -c 'source infra/scripts/common.sh && source infra/scripts/bootstrap-app.sh'
sudo bash -c 'export APP_SERVER_HOST=10.20.1.x; source infra/scripts/common.sh && source infra/scripts/bootstrap-jenkins.sh'
```
