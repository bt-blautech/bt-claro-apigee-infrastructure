# ---------------------------------------------------------------------------
# VPC dedicada de la plataforma (no se usa la VPC "default" del proyecto).
#  - Subred regional: NEG de Private Service Connect (entrada por internet) y futuras cargas
#  - Rango /22 reservado para el peering con el runtime de Apigee (Service Networking)
#  - Sin reglas de firewall de entrada: con PSC y backends Cloud Run no se abre ningun puerto
#    (la regla implicita de la VPC deniega todo el trafico entrante).
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = "${var.name}-vpc"
  description             = "VPC dedicada de la plataforma Apigee ${var.name}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "main" {
  name                     = "${var.name}-subnet-${var.region}"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
  }
}
