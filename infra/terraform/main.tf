# Infraestructura de ejemplo para la demo.
# Contiene malas configuraciones A PROPÓSITO para que Checkov y Trivy
# tengan algo que reportar (y el gate bloquee el despliegue).

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# --- Red -------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = local.tags
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true # ⚠️ IP pública automática
  tags                    = local.tags
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = local.tags
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = local.tags
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Acceso web"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH abierto a internet" # ⚠️
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Todo"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# --- Cómputo ---------------------------------------------------------------

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = false # ⚠️ disco sin cifrar
  }

  # ⚠️ IMDSv1 permitido (sin metadata_options http_tokens = "required")
  tags = local.tags
}

# --- Datos -----------------------------------------------------------------

resource "aws_db_instance" "app" {
  identifier          = "app-db"
  engine              = "postgres"
  engine_version      = "16"
  instance_class      = var.db_instance_class
  allocated_storage   = 100
  username            = "app"
  password            = var.db_password
  storage_encrypted   = false # ⚠️
  publicly_accessible = true  # ⚠️
  skip_final_snapshot = true
  multi_az            = false
  tags                = local.tags
}

resource "aws_s3_bucket" "assets" {
  bucket = "demo-gha-assets-${var.environment}"
  tags   = local.tags
  # ⚠️ sin cifrado, versionado ni bloqueo de acceso público
}

locals {
  tags = {
    Project     = "github-actions-benefits"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
