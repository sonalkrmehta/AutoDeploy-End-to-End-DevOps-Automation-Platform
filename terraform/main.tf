locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

# Latest Ubuntu 24.04 LTS AMI published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Pick an Availability Zone that actually offers the chosen instance type
# (some AZs do not offer every type).
data "aws_ec2_instance_type_offerings" "supported" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

# ---------------------------------------------------------------------------
# Networking: VPC + public subnet + internet gateway + routing
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = sort(data.aws_ec2_instance_type_offerings.supported.locations)[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Firewall: only SSH (for Ansible) and HTTP (Nginx) are reachable.
# Prometheus, Grafana, node-exporter and the app itself are NOT exposed directly;
# Nginx publishes the app on / and Grafana on /grafana/.
# ---------------------------------------------------------------------------

resource "aws_security_group" "app" {
  name_prefix = "${local.name}-sg-"
  description = "AutoDeploy server: SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH (key-based only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description = "HTTP (Nginx reverse proxy)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    description = "All outbound (package repos, image registries)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Compute: key pair + EC2 instance + Elastic IP
# ---------------------------------------------------------------------------

resource "aws_key_pair" "deploy" {
  key_name   = "${local.name}-key"
  public_key = var.ssh_public_key

  tags = {
    Name = "${local.name}-key"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.deploy.key_name
  associate_public_ip_address = true

  # IMDSv2 only; hop limit 1 stops containers from reaching instance metadata.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${local.name}-server"
  }

  lifecycle {
    # A newer Ubuntu AMI must not silently replace (and wipe) a running server.
    ignore_changes = [ami]
  }
}

# Stable public address that survives instance replacement.
resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id

  tags = {
    Name = "${local.name}-eip"
  }

  depends_on = [aws_internet_gateway.main]
}
