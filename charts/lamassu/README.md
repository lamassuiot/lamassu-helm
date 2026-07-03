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
| services.ui.image | string | `"ghcr.io/lamassuiot/lamassu-ui:4.3.0"` | Docker image for UI component |
| services.ca.image | string | `"ghcr.io/lamassuiot/lamassu-ca:3.8.0"` | Docker image for CA component |
| services.va.image | string | `"ghcr.io/lamassuiot/lamassu-va:3.8.0"` | Docker image for VA component |
| services.kms.image | string | `"ghcr.io/lamassuiot/lamassu-kms:3.8.0"` | Docker image for KMS component |
| services.deviceManager.image | string | `"ghcr.io/lamassuiot/lamassu-devmanager:3.8.0"` | Docker image for Device Manager component |
| services.dmsManager.image | string | `"ghcr.io/lamassuiot/lamassu-dmsmanager:3.8.0"` | Docker image for DMS Manager component |
| services.alerts.image | string | `"ghcr.io/lamassuiot/lamassu-alerts:3.8.0"` | Docker image for Alerts component |
| **Replicas & Autoscaling** | | | |
| services.\<svc\>.replicaCount | int | `1` | Number of replicas for the service. Ignored when `autoscaling.enabled` is `true`. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.autoscaling.enabled | bool | `false` | Enable HorizontalPodAutoscaler for the service. When `true`, the `replicas` field is omitted from the Deployment/StatefulSet and managed by the HPA |
| services.\<svc\>.autoscaling.minReplicas | int | `1` | Minimum number of replicas for the HPA |
| services.\<svc\>.autoscaling.maxReplicas | int | `5` | Maximum number of replicas for the HPA |
| services.\<svc\>.autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage for HPA scaling |
| services.\<svc\>.autoscaling.targetMemoryUtilizationPercentage | int | `""` | Target memory utilization percentage for HPA scaling. Optional; omit to disable memory-based scaling |
| **PodDisruptionBudget** | | | |
| services.\<svc\>.pdb.minAvailable | int | `1` | Minimum number of pods that must remain available during node drains and rolling upgrades. PDB is only created when the effective replica count is greater than 1. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| **Pod Affinity & Topology Spread** | | | |
| services.\<svc\>.affinity | object | `{}` | Pod affinity override. `{}` uses the chart default: soft (`preferredDuringScheduling`) pod anti-affinity on `kubernetes.io/hostname`, spreading replicas across nodes. Provide a full [affinity spec](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity) to replace it. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.topologySpreadConstraints | list | `[]` | Topology spread constraints override. `[]` uses the chart defaults: two `ScheduleAnyway` constraints spreading pods across `topology.kubernetes.io/zone` and `kubernetes.io/hostname`. Provide a list of [TopologySpreadConstraint](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) objects to replace them. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| **Resource Requests & Limits** | | | |
| services.\<svc\>.resources.requests.cpu | string | `"100m"` | CPU request. Used by the scheduler for pod placement and required for HPA CPU-based scaling. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.resources.requests.memory | string | `"256Mi"` | Memory request. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.resources.limits.cpu | string | `"500m"` | CPU limit (0.5 vCPU). Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.resources.limits.memory | string | `"1Gi"` | Memory limit (1 GiB). Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| **⚠️ KMS HA Constraint** | | | |
| — | — | — | `services.kms.replicaCount > 1` and `services.kms.autoscaling.enabled: true` are both blocked when the `filesystem` crypto engine is configured (uses a `ReadWriteOnce` PVC). Switch to an external engine (`hashicorp_vault`, `aws_kms`, `aws_secrets_manager`, `pkcs11`) to enable multiple KMS replicas |
| **⚠️ VA HA Constraint** | | | |
| — | — | — | `services.va.replicaCount > 1` requires `fileStore.type` to be changed from `local` to a shared backend (e.g., S3). With `local`, each replica has its own volume and CRL files are not shared across replicas |
| **AWS Connector Replicas & Autoscaling** | | | |
| services.connectors[\*].replicaCount | int | `1` | Number of replicas for a connector instance. Ignored when `autoscaling.enabled` is `true` |
| services.connectors[\*].autoscaling.enabled | bool | `false` | Enable HorizontalPodAutoscaler for the connector instance |
| services.connectors[\*].autoscaling.minReplicas | int | `1` | Minimum number of replicas for the connector HPA |
| services.connectors[\*].autoscaling.maxReplicas | int | `3` | Maximum number of replicas for the connector HPA |
| services.connectors[\*].autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage for connector HPA scaling |
| services.connectors[\*].autoscaling.targetMemoryUtilizationPercentage | int | `""` | Target memory utilization percentage for connector HPA scaling. Optional |
| **CA Service Configuration** | | | |
| services.ca.domains | list | `["dev.lamassu.io"]` | Domains for signing/generating CAs and certificates |
| services.ca.monitoring.frequency | string | `"* * * * *"` | CA health check frequency (CRON syntax, can include seconds) |
| **VA Service Configuration** | | | |
| services.va.fileStore.id | string | `"local-1"` | Unique identifier for the file storage engine instance |
| services.va.fileStore.type | string | `"local"` | Storage backend type. Allowed values: `local`, `s3`. Must be `s3` (or another shared backend) when `replicaCount > 1` |
| services.va.fileStore.local.storageDirectory | string | `"/data/crl"` | Directory on the pod filesystem where CRL files are stored. Only used when `fileStore.type: local`. Backed by a `ReadWriteOnce` PVC — incompatible with `replicaCount > 1` |
| services.va.fileStore.s3 | object | `{}` | Free-form map of S3 config keys injected directly into the `filesystem_storage` config block. Only used when `fileStore.type: s3`. Keys map to `s3.AWSS3FilesystemConfig` + `sharedAWS.AWSSDKConfig` mapstructure field names (e.g. `bucket_name`, `auth_method`, `region`, `access_key_id`, `role_arn`). |
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
| migrations.db.image | string | `"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:3.8.0"` | Docker image for database migrations |
| migrations.db.databases | list | `["alerts", "ca", "va", "devicemanager", "dmsmanager", "kms"]` | List of databases to migrate |
| migrations.caToKms.image | string | `"ghcr.io/lamassuiot/lamassu-ca-to-kms-migration:3.8.0"` | Docker image for the CA-to-KMS migration tool |

