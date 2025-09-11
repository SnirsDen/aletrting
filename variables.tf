variable "project_id" {
  description = "Project ID in GCP"
  type        = string
}

variable "region" {
  description = "Основной регион GCP"
  type        = string
  default     = "europe-west2"
}

variable "prod_zones" {
  description = "Зоны для PROD (europe-west2)"
  type        = list(string)
  default = [
    "europe-west2-a",
    "europe-west2-b"
  ]
}

variable "dev_zones" {
  description = "Зоны для DEV (europe-west3)"
  type        = list(string)
  default = [
    "europe-west3-a",
    "europe-west3-b"
  ]
}
variable "ssh_private_key_path" {
  description = "Path to the private SSH key"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_public_key_path" {
  description = "Path to the public SSH key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
