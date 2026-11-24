# ---------------------------------------------------------------------------
# Solo para orgs de pago (PAYG / SUBSCRIPTION): Apigee exige llaves CMEK para la base de
# datos del runtime y el disco de la instancia. En EVALUATION no se crea nada.
# (Ruta escrita segun la documentacion de Apigee X; la PoC se valida con EVALUATION.)
# ---------------------------------------------------------------------------
locals {
  paid = var.billing_type != "EVALUATION"
}

resource "google_project_service_identity" "apigee" {
  count    = local.paid ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "apigee.googleapis.com"
}

resource "google_kms_key_ring" "apigee" {
  count      = local.paid ? 1 : 0
  name       = "${var.name}-keyring"
  location   = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "apigee" {
  for_each = local.paid ? toset(["db", "disk"]) : toset([])
  name     = "apigee-${each.value}-key"
  key_ring = google_kms_key_ring.apigee[0].id
}

resource "google_kms_crypto_key_iam_member" "apigee" {
  for_each      = google_kms_crypto_key.apigee
  crypto_key_id = each.value.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.apigee[0].email}"
}
