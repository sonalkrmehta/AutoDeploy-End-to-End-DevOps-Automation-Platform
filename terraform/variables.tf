variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used to name and tag every resource."
  type        = string
  default     = "autodeploy"
}

variable "environment" {
  description = "Environment name (used in resource names and tags)."
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 GiB) is comfortable for the app + monitoring stack; t3.micro works with the swap file Ansible creates."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size_gb" {
  description = "Size of the encrypted root EBS volume in GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gb >= 8
    error_message = "root_volume_size_gb must be at least 8."
  }
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet (must be inside vpc_cidr)."
  type        = string
  default     = "10.20.1.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH to the server. GitHub-hosted runners use changing IPs, so the default is open; access is still key-only. Restrict this if you deploy from a fixed IP / self-hosted runner."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to reach the web entrypoint (port 80)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_public_key" {
  description = "SSH public key (contents of the .pub file) installed on the server. Ansible connects with the matching private key."
  type        = string

  validation {
    condition     = startswith(var.ssh_public_key, "ssh-") || startswith(var.ssh_public_key, "ecdsa-")
    error_message = "ssh_public_key must be an OpenSSH public key, e.g. 'ssh-ed25519 AAAA... comment'."
  }
}
