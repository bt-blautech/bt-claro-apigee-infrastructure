output "name" {
  description = "Nombre base de la plataforma (APIGEE_NAME)."
  value       = var.name
}

output "org_id" {
  value = google_apigee_organization.org.id
}

output "instance_name" {
  value = google_apigee_instance.runtime.name
}

output "instance" {
  value = {
    name               = google_apigee_instance.runtime.name
    host               = google_apigee_instance.runtime.host
    service_attachment = google_apigee_instance.runtime.service_attachment
  }
}

output "lb_ip" {
  value = google_compute_global_address.lb_ip.address
}

output "hostnames" {
  description = "Hostname por ambiente (lo usan la capa de ambientes y las variables APIGEE_HOST de GitHub)."
  value       = local.hostnames
}

output "certificate" {
  value = google_compute_managed_ssl_certificate.apigee.name
}

output "cicd_service_account" {
  value = google_service_account.cicd.email
}

output "mock_service_account" {
  value = google_service_account.mock.email
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.poc.repository_id}"
}

output "vault_secrets" {
  value = { for e, s in google_secret_manager_secret.api_secret : e => s.secret_id }
}

output "network" {
  value = {
    vpc          = google_compute_network.vpc.name
    subnet       = "${google_compute_subnetwork.main.name} (${var.subnet_cidr})"
    peering_cidr = var.peering_cidr
  }
}

output "build_service_account" {
  value = google_service_account.build.email
}

output "build_bucket" {
  value = google_storage_bucket.build.name
}
