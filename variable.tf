variable "prefix" {
  type    = string
  default = "aalimsee-tf"
}

variable "createdByTerraform" {
  type    = string
  default = "Managed by Terraform - Aaron"
}

variable "key_pair" {
  type    = string
  default = "aalimsee-keypair"
}

variable "use_https" {
  description = "Controls whether the listener should use port 443 (HTTPS) or 80 (HTTP)."
  type        = bool
  default     = false
  # switch to True, use terraform plan|apply -var="use_https=true"
}

# EC2 instances information
variable "image_id" {
  default = "ami-05576a079321f21f8"
}
variable "instance_type" {
  default = "t2.micro"
}

# Route 53 information
variable "route53_zone" {
  default = "sctp-sandbox.com"
}
variable "route53_subdomain" {
  default = "aalimsee-tf-web"
}



output "web_instances_ip" {
  value = data.aws_instances.asg_instances.public_ips
}
output "db_instances_ip" {
  value = data.aws_instances.db_asg_instances.private_ips
}
