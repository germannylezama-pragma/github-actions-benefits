variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "ami_id" {
  type    = string
  default = "ami-0c02fb55956c7d316" # Amazon Linux 2 (us-east-1)
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "db_password" {
  type      = string
  sensitive = true
  default   = "cambiar-en-secrets" # solo para la demo; en real viene de un secret
}
