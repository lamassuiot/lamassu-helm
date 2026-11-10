# lamassu

PKI for Industrial IoT for Kubernetes

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| lamassuiot |  |  |

## Source Code

* <https://github.com/lamassuiot>
* <https://github.com/lamassuiot/lamassu-kubernetes-chart>

### Template conventions

Every Deployment and StatefulSet is an explicit manifest. Each component owns
its replicas, selectors, containers, probes, ports, volumes, and pod behavior,
so its runtime contract can be read and changed in one file.

Shared helpers are limited to small policies such as effective service values,
metadata, probes, pod placement, Services, HPAs, PDBs, and HTTPRoutes. They do
not render complete workloads or accept pre-rendered YAML. `values.schema.json`
defines the common value types and constraints checked by `helm lint` and
`helm template`.

All chart-owned names are release-scoped and carry the recommended Kubernetes
application labels. Workload pods do not mount service account tokens by
default, use the RuntimeDefault seccomp profile, and drop Linux capabilities.
The chart leaves affinity and topology spread empty unless configured by the
operator.

> **Upgrade notice:** this version changes chart-owned resource names to the
> release-scoped form `<release>-lamassu-<component>`. StatefulSet PVCs are not
> renamed by Kubernetes; plan a data migration or bind existing data before an
> in-place upgrade. AWS connectors are now configured as a map keyed by their
> stable connector ID instead of a list containing `id` fields.

## AMQP TLS

Set `amqp.tls: true` to use AMQPS and configure `amqp.port` to the broker's TLS
listener. System-trusted CA certificates are used by default. To trust a private
CA, create a Secret in the release namespace containing its PEM certificate and
set `amqp.ca.secretName` (and `certificateKey` if the Secret data key is not
`ca.crt`).

For brokers that require mutual TLS, also create a Secret containing the client
certificate and private key, then set `amqp.client.secretName`. The default
Secret data keys are `tls.crt` and `tls.key`; override them with
`certificateKey` and `privateKeyKey` if needed. The chart mounts configured
Secrets read-only into all AMQP-consuming Lamassu pods. These certificate
options require `amqp.tls: true`; the client private key is mounted with
restrictive permissions.
The AMQP client loads TLS certificates at startup, so restart the consuming
pods after updating either Secret.

```yaml
amqp:
  tls: true
  port: 5671
  ca:
    secretName: rabbitmq-ca
  client:
    secretName: lamassu-amqp-client
```

## Secret management

### Problem and goals

Lamassu services need PostgreSQL, AMQP, and optionally SMTP credentials. The
application reads one YAML configuration file, so putting a password directly
in a Helm value would previously make it appear in rendered ConfigMaps and in
the Helm release values. The goals of this implementation are:

1. Keep credentials out of Git-managed values files and ConfigMaps.
2. Keep the chart usable on local kind clusters, EKS, and on-premise clusters.
3. Avoid requiring one particular cloud provider or secret-management product.
4. Preserve compatibility with existing installations during the transition.
5. Make the ownership boundary clear: the chart consumes Secrets; the
   operator or platform team provisions and rotates them.

### Options considered

| Option | Advantages | Disadvantages | Fit for this chart |
|---|---|---|---|
| Kubernetes Secret | Native Kubernetes API; no extra controller; works on kind, EKS, and on-premise | Base64 is encoding, not encryption; provisioning and rotation are external responsibilities | Required runtime interface and lowest common denominator |
| External Secrets Operator | Synchronizes AWS Secrets Manager, Vault, GCP Secret Manager, Azure Key Vault, and others; supports refresh and rotation; Git contains only references | Requires an operator and a provider `SecretStore`/`ClusterSecretStore`; provider IAM and availability must be operated separately | **Recommended provisioning mechanism for production** |
| Sealed Secrets | Encrypted Kubernetes manifests can be stored in Git; convenient for GitOps | Requires a controller and backup of its key; rotation is not automatic; encryption is tied to the controller | Good alternative for clusters without a central secret manager |
| Vault Agent Injector | Vault dynamic secrets, leases, revocation, and strong audit capabilities | Requires Vault, injector webhooks, policies, and pod mutation; more moving parts than this chart needs | Suitable for Vault-centric platforms, but too coupled for a portable application chart |
| SOPS | Encrypts values with KMS, PGP, or age; works well with Git and CI/CD | Decryption must happen in a trusted deployment environment; does not itself refresh running Kubernetes Secrets | Good for GitOps pipelines when ESO is unavailable |
| Helm Secrets plugin | Convenient SOPS integration with Helm commands | Client-side plugin rather than a runtime store; every CI/operator environment needs the plugin and keys | Useful workflow tooling, but not a chart runtime dependency |

### Decision

The chart implements **Kubernetes Secret consumption through `existingSecret`**.
For production, those Secrets should normally be created and refreshed by
**External Secrets Operator**. This gives Lamassu a stable, provider-neutral
interface while allowing each environment to choose its backing store:

- kind: a manually created Kubernetes Secret is sufficient for development.
- EKS: ESO can read AWS Secrets Manager using IRSA or another approved IAM
  integration.
- on-premise: ESO can read Vault or another supported provider, or the
  platform can use Sealed Secrets/SOPS.

ESO, Vault, Sealed Secrets, SOPS, and their provider configuration are
intentionally not installed by this chart. Installing them would make the
application chart provider-specific and could create cluster-wide ownership
conflicts.

### Implementation details

The implementation has four parts:

1. `postgres.existingSecret`, `amqp.existingSecret`, and
   `services.alerts.smtp_server.existingSecret` identify Secrets in the
   release namespace. `usernameKey` and `passwordKey` allow non-standard data
   keys.
2. ConfigMap templates contain non-sensitive placeholders such as
   `__LAMASSU_POSTGRES_PASSWORD__`, never the Secret value. Credential fields
   use YAML single-quoted scalars so double quotes and backslashes in a Secret
   remain literal configuration data.
3. The `lamassu.configSecretInit` helper adds a BusyBox init container. It reads
   credentials through Kubernetes `secretKeyRef`, escapes backslashes for
   `sed` and doubles embedded YAML single quotes, replaces the placeholders,
   and writes the completed configuration to a memory-backed `emptyDir`.
4. The application container mounts the generated file, while the original
   ConfigMap is mounted only as the init container's read-only template.

The `render-config` container runs explicitly as UID/GID `65532`, with
`runAsNonRoot`, privilege escalation disabled, and all Linux capabilities
dropped. The pod uses filesystem group `65532` so the non-root init container
can write the generated file to the shared memory-backed volume and the
application container can read it. This protection also applies to the
database and CA-to-KMS migration hooks.

The helper is parameterized per workload so each init container receives only
the credential families used by its configuration. Regular services receive
PostgreSQL and AMQP credentials, Alerts additionally receives SMTP
credentials, AWS Connector receives AMQP credentials, and migration hooks
receive only the database credentials they need. A missing SMTP Secret therefore
cannot block PostgreSQL preparation or unrelated services.

The same approach is used by the regular workloads, WFX, the database
migration hook, and the optional CA-to-KMS pre-upgrade hook. The CA-to-KMS hook
keeps its compatibility with both the release-scoped and legacy `kms-config`
ConfigMaps, but renders the selected template through the Secret-aware init
container before starting the migration binary. Therefore migration hooks do
not need passwords in command arguments when an `existingSecret` is configured.

The chart still accepts the old `username` and `password` values as a
backwards-compatible fallback. They are intended for local, short-lived
testing only and must not be committed to shared or Git-managed values files.
When both a fallback value and `existingSecret` are supplied, the Secret
reference takes precedence.

### Creating and referencing a Secret

For a local kind cluster, create Secrets outside the values file:

```bash
kubectl -n lamassu create secret generic lamassu-postgres \
  --from-literal=username=lamassu \
  --from-literal=password='change-me'

kubectl -n lamassu create secret generic lamassu-amqp \
  --from-literal=username=lamassu \
  --from-literal=password='change-me'
```

Then reference them from a non-sensitive values file:

```yaml
postgres:
  hostname: postgres.database.svc
  existingSecret: lamassu-postgres
  usernameKey: username
  passwordKey: password
amqp:
  hostname: rabbitmq.messaging.svc
  existingSecret: lamassu-amqp
  usernameKey: username
  passwordKey: password
services:
  alerts:
    smtp_server:
      existingSecret: lamassu-smtp
```

For ESO, create the provider-specific `SecretStore` and `ExternalSecret`
outside this chart. The resulting Kubernetes Secret must contain the keys
configured above and must be created in the same namespace as the Lamassu
release.

### Rotation, security boundaries, and limitations

- Secret values are not copied into chart-managed ConfigMaps.
- Secret values are exposed to the init container as environment variables and
  exist in the generated configuration file inside the pod's memory-backed
  volume. Kubernetes administrators and users with access to the namespace can
  still inspect pod Secrets or process state; this is not a replacement for
  Kubernetes RBAC and encryption at rest.
- Updating a Secret does not rewrite a file already generated in a running
  pod. Restart the affected Lamassu workloads after rotation. A rollout
  annotation or an operator can automate this restart if required.
- The chart does not validate that an external Secret exists or contains the
  configured keys. Kubernetes reports a pod start error when a required
  `secretKeyRef` key is missing.
- The init image is only a rendering utility; it does not fetch secrets from
  external systems and does not need Kubernetes API permissions.
- TLS certificate Secrets for AMQP and the downstream Gateway remain separate
  existing-Secret settings and are mounted directly as files.

## Values

The complete generated values reference is maintained in [VALUES.md](VALUES.md).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.imagePullPolicy | string | `"Always"` | Image pull policy for all containers |
| global.imagePullSecrets | list | `[]` | Image pull secrets applied to every Lamassu pod |
| nameOverride | string | `""` | Partially override release-scoped names |
| fullnameOverride | string | `""` | Fully override the release-scoped name prefix |
| commonLabels | object | `{}` | Labels added to chart-managed resources |
| commonAnnotations | object | `{}` | Annotations added to chart-managed resources |
| serviceAccount.create | bool | `true` | Create a release-scoped ServiceAccount |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the Kubernetes API token into Lamassu pods |
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
| gateway.className | string | `"eg"` | GatewayClass used by the generated Gateway |
| gateway.addresses | list | `[]` | IP addresses for Envoy Gateway (for non-LoadBalancer scenarios) |
| gateway.ports.http | int | `80` | HTTP port for the Gateway |
| gateway.ports.https | int | `443` | HTTPS port for the Gateway |
| gateway.extraRouting | list | `[]` | Additional HTTP routes to expose through the Gateway |
| gateway.responseOverride.unauthorized | object | `{"enabled":true,"contentType":"application/json","body":"{\"error\": \"Unauthorized\"}"}` | Rewrite 401 responses with a custom body on routes behind external authorization (auth=external) |
| gateway.responseOverride.forbidden | object | `{"enabled":true,"contentType":"application/json","body":"{\"error\": \"Forbidden\"}"}` | Rewrite 403 responses with a custom body on routes behind external authorization (auth=external) |
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
| amqp.tls | bool | `false` | Enable AMQP over TLS (AMQPS). Set `port` to the broker's TLS listener port if it differs from `5672`. |
| amqp.ca.secretName | string | `""` | Existing Secret in the release namespace containing the private CA certificate trusted for the AMQP broker. Leave empty to use system-trusted CAs. |
| amqp.ca.certificateKey | string | `"ca.crt"` | Secret data key containing the CA certificate in PEM format. |
| amqp.client.secretName | string | `""` | Existing Secret in the release namespace containing the client certificate and private key for AMQP mutual TLS. Leave empty when the broker does not require a client certificate. |
| amqp.client.certificateKey | string | `"tls.crt"` | Secret data key containing the client certificate in PEM format. |
| amqp.client.privateKeyKey | string | `"tls.key"` | Secret data key containing the client private key in PEM format. |
| **Authentication & Authorization** | | | |
| auth.oidc.frontend.clientId | string | `"frontend"` | OIDC client ID for the frontend |
| auth.oidc.frontend.authority | string | `"https://${window.location.host}/auth/realms/lamassu"` | OIDC provider base URL (can be a JS expression) |
| auth.externalAuthorization.enabled | bool | `true` | Protect routes labeled `auth=external` with Envoy Gateway external authorization |
| auth.externalAuthorization.serviceName | string | `""` | Kubernetes Service name for external authorization; empty derives the release-scoped authz Service |
| auth.externalAuthorization.servicePort | int or null | `null` | Kubernetes Service port for the external authorization endpoint. Defaults to the effective `services.authz.port` |
| auth.externalAuthorization.path | string | `"/v1/ext_authz/check"` | HTTP path that replaces the original request path for the external authorization check. Requires Envoy Gateway v1.8.0+ |
| auth.externalAuthorization.failOpen | bool | `false` | Allow traffic when the external authorization service cannot be reached |
| **Service Images** | | | |
| services.ui.image | string | `"ghcr.io/lamassuiot/lamassu-ui:dev"` | Docker image for UI component |
| services.ca.image | string | `"ghcr.io/lamassuiot/lamassu-ca:dev-v4"` | Docker image for CA component |
| services.va.image | string | `"ghcr.io/lamassuiot/lamassu-va:dev-v4"` | Docker image for VA component |
| services.kms.image | string | `"ghcr.io/lamassuiot/lamassu-kms:dev-v4"` | Docker image for KMS component |
| services.deviceManager.image | string | `"ghcr.io/lamassuiot/lamassu-devmanager:dev-v4"` | Docker image for Device Manager component |
| services.dmsManager.image | string | `"ghcr.io/lamassuiot/lamassu-dmsmanager:dev-v4"` | Docker image for DMS Manager component |
| services.authz.jwkUrl | string | `"http://auth-keycloak/auth/realms/lamassu/protocol/openid-connect/certs"` | JWKS endpoint used by authz to validate JWTs |
| services.authz.insecureSkipJwtVerify | bool | `false` | Skip OIDC JWT signature verification in authz. Unset/false keeps verification ON against services.authz.jwkUrl (production). true is for development/testing only: tokens are parsed without checking signatures. |
| services.wfx.enabled | bool | `true` | Enable the Siemens WFX workflow service |
| services.wfx.image | string | `"ghcr.io/siemens/wfx@sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678"` | Docker image for WFX component, pinned by digest |
| services.wfx.clientPort | int | `9080` | WFX southbound/client API port |
| services.wfx.managementPort | int | `9081` | WFX northbound/management API port |
| services.wfx.logs.format | string | `"json"` | WFX log format |
| services.wfx.logs.level | string | `"debug"` | WFX log level |
| services.wfx.postgres.database | string | `"wfx"` | PostgreSQL database name for WFX |
| services.wfx.postgres.sslmode | string | `"disable"` | PostgreSQL SSL mode for WFX |
| services.wfx.postgres.iamAuth.enabled | bool | `false` | Enable AWS RDS IAM authentication for PostgreSQL |
| services.wfx.postgres.iamAuth.region | string | `""` | AWS region used for PostgreSQL IAM authentication |
| services.wfx.routing.enabled | bool | `true` | Expose WFX through the Lamassu Gateway |
| services.wfx.routing.sbiPath | string | `"/api/wfx/sbi/"` | Gateway path for the WFX southbound/client API |
| services.wfx.routing.nbiPath | string | `"/api/wfx/nbi/"` | Gateway path for the WFX northbound/management API |
| services.wfx.routing.rewritePath | string | `"/api/wfx/"` | Path used when rewriting Gateway routes to WFX |
| services.wfx.extraEnv | list | `[]` | Additional WFX container environment variables |
| services.wfx.extraArgs | list | `[]` | Additional WFX command line arguments |
| services.alerts.image | string | `"ghcr.io/lamassuiot/lamassu-alerts:dev-v4"` | Docker image for Alerts component |
| **Replicas & Autoscaling** | | | |
| services.\<svc\>.replicaCount | int | `1` | Number of replicas for the service. Ignored when `autoscaling.enabled` is `true`. Applies to all services, including `authz` and `wfx` |
| services.\<svc\>.autoscaling.enabled | bool | `false` | Enable HorizontalPodAutoscaler for the service. When `true`, the `replicas` field is omitted from the Deployment/StatefulSet and managed by the HPA |
| services.\<svc\>.autoscaling.minReplicas | int | `1` | Minimum number of replicas for the HPA |
| services.\<svc\>.autoscaling.maxReplicas | int | `5` | Maximum number of replicas for the HPA |
| services.\<svc\>.autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage for HPA scaling |
| services.\<svc\>.autoscaling.targetMemoryUtilizationPercentage | int | `80` | Target memory utilization percentage for HPA scaling |
| **PodDisruptionBudget** | | | |
| services.\<svc\>.pdb.minAvailable | int | `1` | Minimum number of pods that must remain available during node drains and rolling upgrades. PDB is only created when the effective replica count is greater than 1. Applies to all services, including `authz` and `wfx` |
| **Pod Affinity & Topology Spread** | | | |
| services.\<svc\>.affinity | object | `{}` | Kubernetes affinity configuration; no policy is injected by default |
| services.\<svc\>.topologySpreadConstraints | list | `[]` | Kubernetes topology spread constraints; none are injected by default |
| services.\<svc\>.livenessProbe | object | see `values.yaml` | Independent liveness probe configuration |
| services.\<svc\>.readinessProbe | object | see `values.yaml` | Independent readiness probe configuration |
| services.\<svc\>.startupProbe | object | see `values.yaml` | Startup probe configuration for slow-starting services |
| **Resource Requests & Limits** | | | |
| services.\<svc\>.resources.requests.cpu | string | `"100m"` | Default CPU request used by pods and utilization-based HPA metrics |
| services.\<svc\>.resources.requests.memory | string | `"128Mi"` | Default memory request used by pods and utilization-based HPA metrics |
| services.\<svc\>.resources.limits.cpu | string | `"500m"` | Default CPU limit for service containers |
| services.\<svc\>.resources.limits.memory | string | `"512Mi"` | Default memory limit for service containers |
| **⚠️ KMS HA Constraint** | | | |
| — | — | — | `services.kms.replicaCount > 1` and `services.kms.autoscaling.enabled: true` are both blocked when the `filesystem` crypto engine is configured (uses a `ReadWriteOnce` PVC). Switch to an external engine (`hashicorp_vault`, `aws_kms`, `aws_secrets_manager`, `pkcs11`) to enable multiple KMS replicas |
| **⚠️ VA HA Constraint** | | | |
| — | — | — | `services.va.replicaCount > 1` requires `fileStore.type` to be changed from `local` to a shared backend (e.g., S3). With `local`, each replica has its own volume and CRL files are not shared across replicas |
| **AWS Connector Replicas & Autoscaling** | | | |
| services.connectors.\<id\>.type | string | required | Connector type; the map key is the stable connector ID |
| services.connectors.\<id\>.image | string | required | Connector container image |
| services.connectors.\<id\>.replicaCount | int | `1` | Number of replicas for a connector instance. Ignored when `autoscaling.enabled` is `true` |
| services.connectors.\<id\>.autoscaling.enabled | bool | `false` | Enable HorizontalPodAutoscaler for the connector instance |
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
| — | — | — | `cryptoEngines` must live under `services.kms`; `services.ca.cryptoEngines` is rejected by the schema |
| services.kms.cryptoEngines.defaultEngineID | string | `"filesystem-1"` | Default crypto engine ID to use |
| services.kms.cryptoEngines.engines[0].id | string | `"filesystem-1"` | Crypto engine ID |
| services.kms.cryptoEngines.engines[0].type | string | `"filesystem"` | Engine type: `filesystem`, `pkcs11`, `hashicorp_vault`, `aws_kms`, `aws_secrets_manager` |
| services.kms.cryptoEngines.engines[0].storage_directory | string | `"/crypto/fs"` | Storage directory for filesystem engine |
| services.kms.command | list | `[]` | Optional command override for the KMS container, useful for waiting on a forwarded PKCS#11 socket before launch |
| services.kms.args | list | `[]` | Optional arguments override for the KMS container |
| services.kms.pkcs11Sidecar.enabled | bool | `false` | Deploy a sidecar that creates a PKCS#11 socket on a shared volume for KMS. Requires Kubernetes 1.29+ |
| services.kms.pkcs11Sidecar.image | string | `""` | Sidecar image used to create the forwarded PKCS#11 socket |
| services.kms.pkcs11Sidecar.imagePullPolicy | string | `"IfNotPresent"` | Image pull policy for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.securityContext | object | `{}` (merged from KMS's 65532:65532 security context) | Security context for the PKCS#11 sidecar. Defaults to KMS's own; its forwarded socket is mode-0660 and accessible to KMS through the pod's fsGroup |
| services.kms.pkcs11Sidecar.socketDir | string | `"/run/p11-kit"` | Shared directory where the sidecar should create the PKCS#11 socket |
| services.kms.pkcs11Sidecar.command | list | `[]` | Command for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.args | list | `[]` | Arguments for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.env | list | `[]` | Extra environment variables for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.volumeMounts | list | `[]` | Extra sidecar volume mounts, for example SSH key secrets |
| services.kms.pkcs11Sidecar.volumes | list | `[]` | Extra pod volumes needed by the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.resources | object | `{}` | Resource requests and limits for the PKCS#11 sidecar |
| services.kms.pkcs11Modules | list | `[]` | Optional PKCS#11 modules injected into KMS at runtime by short-lived init containers. Each entry supports `name`, `image`, `imagePullPolicy`, `securityContext`, `command`, `args`, `env`, and `mountPath` |
| **Multi-HSM Deployment** | | | |
| services.kms.cryptoEngines.engines[0].module_path | string | `"/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so"` | PKCS#11 client module to use when the HSM socket is forwarded |
| services.kms.pkcs11Sidecar.socketDir | string | `"/run/p11-kit"` | Shared directory used by the sidecar and the KMS container for the forwarded socket |

When the KMS image is responsible for the PKCS#11 client environment, the chart
only needs to make the forwarded socket available inside the pod. Enable the
sidecar and have it create the socket in the shared directory.

For multiple HSMs, deploy multiple KMS releases instead of trying to multiplex
them inside a single pod. Each release should point at exactly one HSM/socket
pair, for example:

- Release `kms-a` mounts `/run/p11-kit-a` and its sidecar forwards HSM `a`
- Release `kms-b` mounts `/run/p11-kit-b` and its sidecar forwards HSM `b`

This keeps token state, socket ownership, and failure domains isolated.

| **Alerts Service Configuration** | | | |
| services.alerts.smtp_server.from | string | `""` | Email address for alert sender |
| services.alerts.smtp_server.host | string | `""` | SMTP server hostname |
| services.alerts.smtp_server.port | int | `25` | SMTP server port |
| services.alerts.smtp_server.username | string | `""` | SMTP username |
| services.alerts.smtp_server.password | string | `""` | SMTP password |
| services.alerts.smtp_server.enable_ssl | bool | `true` | Enable TLS for SMTP connection |
| services.alerts.smtp_server.insecure | bool | `false` | Skip TLS certificate verification |
| **Connectivity Test & Migrations** | | | |
| connectivityTest.image | string | `"curlimages/curl@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777"` | Image for the `helm test` connectivity-check hook |
| connectivityTest.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Security context for the connectivity-check hook container |
| migrations.db.image | string | `"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:dev-v4"` | Docker image for database migrations |
| migrations.db.databases | list | `["alerts", "kms", "ca", "va", "devicemanager", "dmsmanager"]` | List of databases to migrate |
| migrations.caToKms.image | string | `"ghcr.io/lamassuiot/lamassu-ca-to-kms-migration:dev-v4"` | Docker image for the CA-to-KMS migration tool |

### In-Cluster HSM over `p11-kit`

Use this mode when the HSM endpoint is another pod or StatefulSet inside the
cluster and only the KMS sidecar should connect to it.

The flow is:

1. The HSM pod runs `p11-kit server` and `sshd`.
2. The KMS PKCS#11 sidecar opens an SSH session to the internal HSM Service.
3. That sidecar forwards the HSM socket into the shared `socketDir` with
   `ssh -L`.
4. Lamassu KMS uses `p11-kit-client.so` and `P11_KIT_SERVER_ADDRESS` to talk
   to the forwarded token.

The sidecar defines a `readinessProbe` that checks for the forwarded socket,
and Kubernetes' native-sidecar semantics (1.29+) block the main KMS container
from starting until that probe passes — no extra wait-loop or command
override is needed on the KMS container itself for the tunnel to be ready in
time.

Example values: [ci/pkcs11-incluster-hsm-values.yaml](ci/pkcs11-incluster-hsm-values.yaml)

Build the proxy image from [ci/softhsm/proxy.dockerfile](../../../ci/softhsm/proxy.dockerfile), then configure:

```yaml
services:
  kms:
    # The sidecar forwards the socket as mode 0660. Set fsGroup to the
    # sidecar's group when KMS and the sidecar use different UIDs.
    podSecurityContext:
      fsGroup: 0
    pkcs11Sidecar:
      enabled: true
      securityContext:
        runAsGroup: 0
      image: ghcr.io/lamassuiot/p11-kit-ssh-sidecar:ci-test
      env:
        - name: SSH_DESTINATION
          value: root@hsm-softhsm
        - name: SSH_IDENTITY_FILE
          value: /etc/p11-kit-ssh/id_ed25519
      volumeMounts:
        - name: kms-pkcs11-ssh-key
          mountPath: /etc/p11-kit-ssh
          readOnly: true
      volumes:
        - name: kms-pkcs11-ssh-key
          secret:
            secretName: kms-pkcs11-sidecar-ssh-key
    # Stage a p11-kit-client.so that matches the HSM's p11-kit server version
    # into a shared, read-only volume with a pkcs11Modules init container (see
    # charts/lamassu/ci/pkcs11-incluster-hsm-values.yaml for the full staging script).
    pkcs11Modules:
      - name: p11-kit-client
        image: ubuntu:26.04
        mountPath: /run/p11-kit-modules
        # ... stages p11-kit-client.so and its non-core dependencies, see the example values file
    cryptoEngines:
      defaultEngineID: pkcs11-1
      engines:
        - id: pkcs11-1
          type: pkcs11
          token: "your-token-label"
          pin: "1234"
          module_path: "/run/p11-kit-modules/p11-kit-client.so"
          module_extra_options:
            env:
              P11_KIT_SERVER_ADDRESS: "unix:path=/run/p11-kit/pkcs11"
              LD_LIBRARY_PATH: "/run/p11-kit-modules"
```

On the proxy sidecar, the image runs an SSH client roughly equivalent to:

```bash
ssh -N \
  -o ExitOnForwardFailure=yes \
  -o StreamLocalBindUnlink=yes \
  -L /run/p11-kit/pkcs11:/run/p11-kit/pkcs11 \
  -i /etc/p11-kit-ssh/id_ed25519 \
  root@hsm-softhsm
```

Notes:

- Kubernetes 1.29 or newer is required when `services.kms.pkcs11Sidecar.enabled=true`.
  This feature relies on native sidecar initContainer semantics (`restartPolicy: Always`).
- The HSM Service can stay `ClusterIP`; no KMS-side SSH Service is required.
- The HSM pod must accept the sidecar's SSH public key and expose port `22`
  internally.
- `p11-kit-client.so` must be RPC-compatible with the HSM's `p11-kit server`;
  mixing minor versions fails (for example, a 0.24 client against a 0.26
  server returns `CKR_DEVICE_MEMORY` on key generation). The bundled SoftHSM
  image ships p11-kit 0.26 (`ubuntu:26.04`); KMS images built before the
  matching client update bundle 0.24, so stage the client as shown above.
- If KMS starts before the tunnel is ready, use `services.kms.command/args`
  to wait until `/run/p11-kit/pkcs11` exists before launching the real binary.
