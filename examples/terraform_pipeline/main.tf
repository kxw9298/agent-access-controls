# Demo configuration for the approval-binding demonstration.
#
# It uses only the built-in terraform_data resource, so it needs no cloud
# account, credentials, or provider download. The "release" variable stands
# in for whatever an agent might change between approval and apply.

terraform {
  required_version = ">= 1.4"
}

variable "release" {
  description = "Release identifier written into the demo resource."
  type        = string
  default     = "v1"
}

resource "terraform_data" "service_config" {
  input = {
    release = var.release
  }
}

output "release" {
  value = terraform_data.service_config.output.release
}
