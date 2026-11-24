output "hostnames" {
  description = "Hostname de Apigee por ambiente -> variable APIGEE_HOST del repo de APIs."
  value       = { for e in keys(var.environments) : e => local.boot.hostnames[e] }
}

output "backend_hosts" {
  description = "Host del backend de prueba por ambiente -> variable BACKEND_HOST del repo de APIs."
  value       = { for e, s in google_cloud_run_v2_service.mock : e => trimprefix(s.uri, "https://") }
}

output "truststore_refs" {
  description = "Referencia del truststore por ambiente (las APIs la usan en el target server)."
  value       = { for e, r in google_apigee_env_references.truststore : e => "ref://${r.name}" }
}

output "environments" {
  value = keys(var.environments)
}
