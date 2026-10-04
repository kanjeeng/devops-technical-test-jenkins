# Troubleshooting

| Gejala | Penyebab / solusi |
|---|---|
| Jenkins UI tidak terbuka | Bootstrap belum selesai (`tail /var/log/bootstrap.log`) atau IP Anda berubah → update `allowed_admin_cidrs` lalu `terraform apply` |
| `go: command not found` di pipeline | Cek `ls -l /usr/local/bin/go`; restart Jenkins: `sudo systemctl restart jenkins` |
| `permission denied ... docker.sock` | User `jenkins` belum di grup docker: `sudo usermod -aG docker jenkins && sudo systemctl restart jenkins` |
| `Host tujuan deploy kosong` | Env global `APP_SERVER_HOST` kosong → isi parameter `APP_HOST` dengan output `app_private_ip` |
| SSH `Permission denied (publickey)` di Deploy | Credential `app-server-ssh` salah: username harus `ubuntu`, isi key lengkap termasuk baris BEGIN/END |
| SSH timeout dari Jenkins | Gunakan IP **private** app; SG app mengizinkan 22 dari SG Jenkins |
| Stage Verify gagal | Port 8080 di app server; cek `docker logs hello-devops` dan `docker ps` |
| Container restart terus | `docker logs hello-devops`; binary rusak → jalankan rollback: `cp /opt/hello-devops/bin/.server.previous /opt/hello-devops/bin/server && docker restart hello-devops` |
| Port 8080 sudah dipakai (lokal) | `HOST_PORT=8081 ./scripts/run.sh` |
| `terraform apply` error credentials | `aws sts get-caller-identity`; cek region & permission IAM |
| Terraform: `allowed_admin_cidrs` required | Buat `terraform.tfvars` dari contoh |
