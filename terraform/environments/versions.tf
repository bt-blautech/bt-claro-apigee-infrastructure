terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  # Estado de la capa de AMBIENTES (el bootstrap usa el prefix apigee-bootstrap)
  backend "gcs" {
    prefix = "apigee-environments"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
