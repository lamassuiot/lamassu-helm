# lamassu

PKI for Industrial IoT for Kubernetes

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| lamassuiot |  |  |

## Source Code

* <https://github.com/lamassuiot>
* <https://github.com/lamassuiot/lamassu-kubernetes-chart>


## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.imagePullPolicy | string | `"Always"` | Image pull policy for all containers |
| **TLS Configuration** | | | |
| tls.type | string | `"certManager"` | TLS certificate provider. Allowed values: `certManager`, `external` |
| tls.certManagerOptions.clusterIssuer | string | `""` | CertManager ClusterIssuer to use to sign the certificate |
| tls.certManagerOptions.issuer | string | `""` | CertManager Issuer to use (ignored if clusterIssuer is set) |
| tls.certManagerOptions.certSpec.commonName | string | `"dev.lamassu.io"` | Common name for the certificate |
| tls.certManagerOptions.certSpec.hostnames | list | `["dev.lamassu.io"]` | DNS names to include in the certificate |
| tls.certManagerOptions.certSpec.addresses | list | `[]` | IP addresses to include in the certificate |
| tls.certManagerOptions.certSpec.duration | string | `"2160h"` | Certificate validity duration (90 days) |
| tls.externalOptions.secretName | string | `""` | Secret name for external TLS certificate (must have `tls.crt` and `tls.key` keys) |
| **Gateway Configuration** | | | |
| gateway.addresses | list | `[]` | IP addresses for Envoy Gateway (for non-LoadBalancer scenarios) |
| gateway.ports.http | int | `80` | HTTP port for the Gateway |
| gateway.ports.https | int | `443` | HTTPS port for the Gateway |
| gateway.extraRouting | list | `[]` | Additional HTTP routes to expose through the Gateway |
| **Database Configuration** | | | |
| postgres.hostname | string | `""` | PostgreSQL server hostname |
| postgres.port | int | `5432` | PostgreSQL server port |
| postgres.username | string | `""` | PostgreSQL username |
| postgres.password | string | `""` | PostgreSQL password |
| **Message Queue Configuration** | | | |
| amqp.hostname | string | `""` | AMQP server hostname |
| amqp.port | int | `5672` | AMQP server port |
| amqp.username | string | `""` | AMQP username |
| amqp.password | string | `""` | AMQP password |
| amqp.tls | bool | `false` | Enable AMQP over TLS (AMQPS) |
| **Authentication & Authorization** | | | |
| auth.oidc.frontend.clientId | string | `"frontend"` | OIDC client ID for the frontend |
| auth.oidc.frontend.authority | string | `"https://${window.location.host}/auth/realms/lamassu"` | OIDC provider base URL (can be a JS expression) |
| auth.oidc.apiGateway.jwks[0].name | string | `"oidc-authn"` | Name for the JWKS provider |
| auth.oidc.apiGateway.jwks[0].uri | string | `"http://keycloak/..."` | URI to fetch the public key set for JWT validation |
| auth.authorization.rolesClaim | string | `"realm_access.roles"` | JWT claim to extract user roles from |
| auth.authorization.roles.admin | string | `"pki-admin"` | Role for Lamassu admin users |
| **Service Images** | | | |
| services.ui.image | string | `"ghcr.io/lamassuiot/lamassu-ui:4.2.0"` | Docker image for UI component |
| services.ca.image | string | `"ghcr.io/lamassuiot/lamassu-ca:3.7.0"` | Docker image for CA component |
| services.va.image | string | `"ghcr.io/lamassuiot/lamassu-va:3.7.0"` | Docker image for VA component |
| services.kms.image | string | `"ghcr.io/lamassuiot/lamassu-kms:3.7.0"` | Docker image for KMS component |
| services.deviceManager.image | string | `"ghcr.io/lamassuiot/lamassu-devmanager:3.7.0"` | Docker image for Device Manager component |
| services.dmsManager.image | string | `"ghcr.io/lamassuiot/lamassu-dmsmanager:3.7.0"` | Docker image for DMS Manager component |
| services.alerts.image | string | `"ghcr.io/lamassuiot/lamassu-alerts:3.7.0"` | Docker image for Alerts component |
| **CA Service Configuration** | | | |
| services.ca.domains | list | `["dev.lamassu.io"]` | Domains for signing/generating CAs and certificates |
| services.ca.monitoring.frequency | string | `"* * * * *"` | CA health check frequency (CRON syntax, can include seconds) |
| **VA Service Configuration** | | | |
| services.va.fileStore.id | string | `"local-1"` | File store ID for VA |
| services.va.fileStore.type | string | `"local"` | File store type |
| services.va.fileStore.storageDirectory | string | `"/data/crl"` | Storage directory for CRLs |
| services.va.job.crl.frequency | string | `"* * * * *"` | CRL computation job frequency (CRON syntax) |
| **KMS Service Configuration** | | | |
| services.kms.cryptoEngines.defaultEngineID | string | `"filesystem-1"` | Default crypto engine ID to use |
| services.kms.cryptoEngines.engines[0].id | string | `"filesystem-1"` | Crypto engine ID |
| services.kms.cryptoEngines.engines[0].type | string | `"filesystem"` | Engine type: `filesystem`, `pkcs11`, `hashicorp_vault`, `aws_kms`, `aws_secrets_manager` |
| services.kms.cryptoEngines.engines[0].storage_directory | string | `"/crypto/fs"` | Storage directory for filesystem engine |
| **Alerts Service Configuration** | | | |
| services.alerts.smtp_server.from | string | `""` | Email address for alert sender |
| services.alerts.smtp_server.host | string | `""` | SMTP server hostname |
| services.alerts.smtp_server.port | int | `25` | SMTP server port |
| services.alerts.smtp_server.username | string | `""` | SMTP username |
| services.alerts.smtp_server.password | string | `""` | SMTP password |
| services.alerts.smtp_server.enable_ssl | bool | `true` | Enable TLS for SMTP connection |
| services.alerts.smtp_server.insecure | bool | `false` | Skip TLS certificate verification |
| **Toolbox & Migrations** | | | |
| toolbox.image | string | `"ghcr.io/lamassuiot/toolbox:2.2.0"` | Docker image for toolbox utility |
| migrations.image | string | `"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:3.7.0"` | Docker image for database migrations |
| migrations.databases | list | `["auth", "alerts", "ca", "va", "cloudproxy", "devicemanager", "dmsmanager", "kms"]` | List of databases to migrate |

