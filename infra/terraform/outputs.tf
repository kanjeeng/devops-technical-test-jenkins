output "jenkins_url" {
  description = "URL Jenkins UI"
  value       = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "app_url" {
  description = "URL aplikasi (aktif setelah pipeline pertama sukses)"
  value       = "http://${aws_eip.app.public_ip}:8080"
}

output "app_private_ip" {
  description = "IP private app server (tujuan deploy dari Jenkins)"
  value       = aws_instance.app.private_ip
}

output "ssh_jenkins" {
  description = "Perintah SSH ke Jenkins Server"
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_eip.jenkins.public_ip}"
}

output "ssh_app" {
  description = "Perintah SSH ke App Server"
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_eip.app.public_ip}"
}

output "private_key_file" {
  description = "Private key untuk SSH & credential Jenkins 'app-server-ssh'"
  value       = local_sensitive_file.private_key.filename
}

output "get_jenkins_password" {
  description = "Perintah mengambil initial admin password Jenkins"
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_eip.jenkins.public_ip} 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword'"
}