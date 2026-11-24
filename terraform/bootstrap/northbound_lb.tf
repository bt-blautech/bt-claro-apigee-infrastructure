# ---------------------------------------------------------------------------
# Entrada por internet: IP global + HTTPS LB (EXTERNAL_MANAGED) + backend Private Service
# Connect hacia el service attachment de la instancia (sin VMs puente) + certificado gestionado
# con un hostname por environment group. Los hostnames se derivan de la IP o de var.domain.
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "lb_ip" {
  name       = "${var.name}-lb-ip"
  depends_on = [google_project_service.apis]
}

locals {
  base_domain = var.domain != "" ? var.domain : "${google_compute_global_address.lb_ip.address}.nip.io"
  hostnames   = { for e in var.environments : e => "${e}.${local.base_domain}" }
}

resource "google_compute_region_network_endpoint_group" "psc_neg" {
  name                  = "${var.name}-psc-neg"
  region                = var.region
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = google_apigee_instance.runtime.service_attachment
  network               = local.network_id
  subnetwork            = google_compute_subnetwork.main.id
}

resource "google_compute_backend_service" "apigee" {
  name                  = "${var.name}-backend"
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 60
  backend {
    group = google_compute_region_network_endpoint_group.psc_neg.id
  }
  log_config {
    enable = true
  }
}

resource "google_compute_url_map" "apigee" {
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_service.apigee.id
}

resource "google_compute_managed_ssl_certificate" "apigee" {
  name = "${var.name}-cert-${substr(sha1(join(",", values(local.hostnames))), 0, 8)}"
  managed {
    domains = values(local.hostnames)
  }
  lifecycle {
    create_before_destroy = true # al cambiar hostnames: certificado nuevo antes de quitar el anterior
  }
}

resource "google_compute_target_https_proxy" "apigee" {
  name             = "${var.name}-https-proxy"
  url_map          = google_compute_url_map.apigee.id
  ssl_certificates = [google_compute_managed_ssl_certificate.apigee.id]
}

resource "google_compute_global_forwarding_rule" "apigee" {
  name                  = "${var.name}-https-fr"
  target                = google_compute_target_https_proxy.apigee.id
  ip_address            = google_compute_global_address.lb_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
