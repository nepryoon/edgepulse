variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type = string
}

# Optional if you later attach routes / DNS
variable "cloudflare_zone_id" {
  type    = string
  default = ""
}

variable "project_name" {
  type    = string
  default = "edgepulse"
}

variable "db_name" {
  type    = string
  default = "edgepulse"
}

variable "db_username" {
  type    = string
  default = "edgepulse"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
