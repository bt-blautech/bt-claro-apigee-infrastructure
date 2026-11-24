# ---------------------------------------------------------------------------
# Validacion de la entrada por internet. Terraform crea el certificado gestionado pero NO
# espera su emision (15-60 min). Estos checks se evaluan en cada plan/apply y ADVIERTEN si un
# hostname no negocia TLS valido. El bloqueo duro esta en scripts/check_platform.sh.
# ---------------------------------------------------------------------------
check "lb_tls_dev" {
  data "http" "dev" {
    url = "https://${try(local.hostnames["dev"], values(local.hostnames)[0])}/"
  }
  assert {
    condition     = data.http.dev.status_code > 0
    error_message = "El hostname de dev no negocia TLS: certificado aun no ACTIVE o DNS sin apuntar a la IP del LB."
  }
}

check "lb_tls_qa" {
  data "http" "qa" {
    url = "https://${try(local.hostnames["qa"], values(local.hostnames)[0])}/"
  }
  assert {
    condition     = data.http.qa.status_code > 0
    error_message = "El hostname de qa no negocia TLS: certificado aun no ACTIVE o DNS sin apuntar a la IP del LB."
  }
}
