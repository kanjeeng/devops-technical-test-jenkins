variable "aws_region" {
  description = "Region AWS"
  type        = string
  default     = "ap-southeast-1" # Singapore
}

variable "project_name" {
  description = "Prefix nama resource"
  type        = string
  default     = "hello-devops"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.20.1.0/24"
}

variable "allowed_admin_cidrs" {
  description = "CIDR yang boleh akses SSH (22) & Jenkins UI (8080). Contoh: [\"203.0.113.10/32\"]. Cek IP: curl -s https://checkip.amazonaws.com"
  type        = list(string)
}

variable "app_ingress_cidrs" {
  description = "CIDR yang boleh akses aplikasi di port 8080"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium" # 2 vCPU / 4 GB - Jenkins + Docker build
}

variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "jenkins_volume_size" {
  description = "Ukuran root disk Jenkins (GB)"
  type        = number
  default     = 30
}

variable "app_volume_size" {
  description = "Ukuran root disk app server (GB)"
  type        = number
  default     = 15
}

variable "go_version" {
  description = "Versi Go yang diinstal di server Jenkins"
  type        = string
  default     = "1.22.10"
}
