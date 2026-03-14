variable "aws_region" {
  default = "us-east-1"
}

variable "anthropic_api_key" {
  type      = string
  sensitive = true
}

variable "google_credentials_path" {
  type    = string
  default = "/var/task/google-service-account.json"
}

variable "gcp_project_id" {
  type = string
}
