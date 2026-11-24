# Certificados por ambiente (truststores de Apigee)

Solo **certificados públicos de CA** en PEM. Cada `certs/<env>/*.pem` se carga como un alias del truststore
`ts-backend-<env>` de ese ambiente (Terraform), y el target server exige validar el TLS del backend
(`enforce = true`) cuando el ambiente tiene al menos un certificado.

| Archivo | Origen | Uso |
|---|---|---|
| `gts-root-r4.pem` | https://pki.goog/repo/certs/gtsr4.pem (Google Trust Services) | Raíz de la cadena ECDSA que presenta Cloud Run (`*.a.run.app` → WE2 → GTS Root R4). Verificada con `openssl verify`. |
| `gts-root-r1.pem` | https://pki.goog/repo/certs/gtsr1.pem | Raíz de la cadena RSA alternativa de Google. |

Con backends propios de Claro, reemplazar por la CA de cada ambiente (por ejemplo, una CA interna distinta en DEV y QA).
Nunca subir llaves privadas (`*.key`, `*.p12`, `*.jks`): están bloqueadas en `.gitignore` y gitleaks las detecta.
