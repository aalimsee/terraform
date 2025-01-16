variable "prefix" {
  type = string
  default = "aalimsee-tf"
}

variable "createdByTerraform" {
  type = string
  default = "Managed by Terraform - Aaron"
}

variable "key-pair" {
  type = string
  default = "aalimsee-keypair"
}

variable "use_https" {
  description = "Controls whether the listener should use port 443 (HTTPS) or 80 (HTTP)."
  type        = bool
  default     = false
  # switch to True, use terraform plan|apply -var="use_https=true"
}
