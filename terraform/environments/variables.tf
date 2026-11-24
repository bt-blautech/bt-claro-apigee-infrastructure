variable "project_id" {
  description = "Proyecto GCP / organizacion Apigee X."
  type        = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "state_bucket" {
  description = "Bucket del estado de Terraform (el bootstrap usa el prefix apigee-bootstrap)."
  type        = string
}

variable "environments" {
  description = "Ambientes de la plataforma: environment group, backend de prueba (Cloud Run) y truststore."
  type = map(object({
    envgroup           = string
    mock_service       = string
    mock_min_instances = optional(number, 1)
    truststore         = string
  }))
  default = {
    dev = { envgroup = "eg-dev", mock_service = "mock-customers-dev", truststore = "ts-backend-dev" }
    qa  = { envgroup = "eg-qa", mock_service = "mock-customers-qa", truststore = "ts-backend-qa" }
  }
}

variable "mock_image_tag" {
  description = "Tag de la imagen del backend mock publicada por scripts/build_mock.sh."
  type        = string
  default     = "1.0.0"
}
