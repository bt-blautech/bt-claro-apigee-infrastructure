variable "project_id" {
  description = "Proyecto GCP. En Apigee X el nombre de la organizacion = project_id."
  type        = string
}

variable "name" {
  description = "Nombre base de la plataforma (APIGEE_NAME): prefija instancia, LB, certificado, registro, vault y SAs. La org siempre es el project_id."
  type        = string
  default     = "poc"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,18}[a-z0-9]$", var.name))
    error_message = "name: 3-20 caracteres, minusculas, digitos y guiones; empieza con letra (limite por los IDs de service account)."
  }
}

variable "region" {
  description = "Region de analytics, del runtime y de los recursos regionales."
  type        = string
  default     = "us-central1"
}

variable "subnet_cidr" {
  description = "Rango de la subred de la VPC dedicada (region var.region). No debe solaparse con peering_cidr ni con redes de Claro."
  type        = string
  default     = "10.10.0.0/24"
}

variable "peering_cidr" {
  description = "Rango reservado para el peering con Apigee (evaluacion: /22). No debe solaparse con subnet_cidr."
  type        = string
  default     = "10.20.0.0/22"
}

variable "billing_type" {
  description = "EVALUATION (60 dias, sin costo de Apigee), PAYG o SUBSCRIPTION (requieren KMS: ver kms.tf)."
  type        = string
  default     = "EVALUATION"
  validation {
    condition     = contains(["EVALUATION", "PAYG", "SUBSCRIPTION"], var.billing_type)
    error_message = "billing_type debe ser EVALUATION, PAYG o SUBSCRIPTION."
  }
}

variable "org_description" {
  type    = string
  default = "PoC CI/CD Apigee - Claro CENAM"
}

variable "peering_range_description" {
  type    = string
  default = "Rango para el peering con Apigee X"
}

variable "environments" {
  description = "Ambientes de la PoC: un hostname, un secreto de vault y un environment group por ambiente."
  type        = list(string)
  default     = ["dev", "qa"]
}

variable "domain" {
  description = "Dominio propio para los hostnames (dev.<domain>). Vacio = <env>.<IP-del-LB>.nip.io (sin DNS propio)."
  type        = string
  default     = ""
}

variable "cicd_roles" {
  description = "Roles de la SA de GitHub Actions (lineamientos: apigee.admin y apigee.deployer)."
  type        = list(string)
  default     = ["roles/apigee.admin", "roles/apigee.deployer"]
}
