locals {
  network_id = google_compute_network.vpc.id
}

# ---------------------------------------------------------------------------
# APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "apigee.googleapis.com", "compute.googleapis.com", "servicenetworking.googleapis.com",
    "cloudkms.googleapis.com", "cloudresourcemanager.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Red: rango reservado + Service Networking (peering VPC <-> Apigee)
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "apigee_range" {
  name          = "${var.name}-apigee-range"
  description   = var.peering_range_description
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(var.peering_cidr, 0)
  prefix_length = tonumber(split("/", var.peering_cidr)[1])
  network       = local.network_id
  depends_on    = [google_project_service.apis]
}

resource "google_service_networking_connection" "apigee" {
  network                 = local.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.apigee_range.name]
  deletion_policy         = "ABANDON" # el peering lo libera Google al borrar la instancia
}

# ---------------------------------------------------------------------------
# Organizacion Apigee X (30-60 min) e instancia regional
# En produccion agregar lifecycle { prevent_destroy = true } a ambas.
# ---------------------------------------------------------------------------
resource "google_apigee_organization" "org" {
  project_id                           = var.project_id
  description                          = var.org_description
  analytics_region                     = var.region
  runtime_type                         = "CLOUD"
  billing_type                         = var.billing_type
  authorized_network                   = google_compute_network.vpc.name
  runtime_database_encryption_key_name = local.paid ? google_kms_crypto_key.apigee["db"].id : null
  depends_on                           = [google_service_networking_connection.apigee, google_kms_crypto_key_iam_member.apigee]

  # Se declara explicito: un valor vacio en el estado hace fallar el DELETE de la org (Error 400 'retention')
  retention = "DELETION_RETENTION_UNSPECIFIED"
}

resource "google_apigee_instance" "runtime" {
  name                     = "${var.name}-instance"
  location                 = var.region
  org_id                   = google_apigee_organization.org.id
  disk_encryption_key_name = local.paid ? google_kms_crypto_key.apigee["disk"].id : null
}
