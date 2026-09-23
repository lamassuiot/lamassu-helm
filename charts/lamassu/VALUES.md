# lamassu

![Version: 3.8.0](https://img.shields.io/badge/Version-3.8.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.8.0](https://img.shields.io/badge/AppVersion-3.8.0-informational?style=flat-square)

PKI for Industrial IoT for Kubernetes

**Homepage:** <https://lamassu.io>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| lamassuiot |  | <https://github.com/lamassuiot> |

## Source Code

* <https://github.com/lamassuiot>
* <https://github.com/lamassuiot/lamassu-kubernetes-chart>

## Requirements

Kubernetes: `>=1.24.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| amqp.hostname | string | `""` | Hostname for the AMQP server |
| amqp.password | string | `""` | Password to be used to authenticate with the AMQP server |
| amqp.port | int | `5672` | Port for the AMQP server |
| amqp.tls | bool | `false` | Enable AMQP over TLS (aka AMPQS) |
| amqp.username | string | `""` | Username to be used to authenticate with the AMQP server |
| auth.authorization.roles.admin | string | `"pki-admin"` | Role association to be used to authorize the user as LAMASSU's admin |
| auth.authorization.rolesClaim | string | `"realm_access.roles"` | Claim to use to find and filter the user's roles |
| auth.externalAuthorization.enabled | bool | `true` | Protect routes labeled auth=external with Envoy Gateway external authorization. |
| auth.externalAuthorization.failOpen | bool | `false` | Allow traffic when the external authorization service cannot be reached. |
| auth.externalAuthorization.path | string | `"/v1/ext_authz/check"` | HTTP path that replaces the original request path for the external authorization check. Requires Envoy Gateway v1.8.0+. |
| auth.externalAuthorization.serviceName | string | `""` | Kubernetes Service name for the external authorization endpoint. Empty uses the release-scoped authz Service. |
| auth.externalAuthorization.servicePort | string | `nil` | Kubernetes Service port for the external authorization endpoint. Defaults to the effective services.authz.port. |
| auth.oidc.apiGateway.jwks | list | `[{"name":"oidc-authn","uri":"http://keycloak/auth/realms/lamassu/protocol/openid-connect/certs"}]` | URL pointing to the issuer's public key set to validate the JWT tokens. |
| auth.oidc.apiGateway.jwks[0].uri | string | `"http://keycloak/auth/realms/lamassu/protocol/openid-connect/certs"` | URI to use to fetch the public key set |
| auth.oidc.frontend.authority | string | `"https://${window.location.host}/auth/realms/lamassu"` | URL pointing to the OIDC provider's base path to build the OIDC well-known URL (This is the complete URL preceding the "/.well-known/openid-configuration" URL). Can be a JS expression |
| auth.oidc.frontend.clientId | string | `"frontend"` | Client ID to be used as the OIDC client for the frontend |
| commonAnnotations | object | `{}` | Annotations added to every chart-managed object. |
| commonLabels | object | `{}` | Labels added to every chart-managed object. Selector labels remain chart controlled. |
| connectivityTest.image | string | `"curlimages/curl@sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69"` | Image for the `helm test` connectivity-check hook. The public,    upstream-maintained curl image (pinned by digest) rather than a    chart-owned image, since the hook only needs curl and a POSIX shell. |
| connectivityTest.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Security context for the connectivity-check hook container. |
| fullnameOverride | string | `""` | Fully override the release-scoped resource-name prefix. |
| gateway.addresses | string | `nil` |  |
| gateway.className | string | `"eg"` | GatewayClass used by the generated Gateway. |
| gateway.extraRouting | string | `nil` |  |
| gateway.ports.http | int | `80` |  |
| gateway.ports.https | int | `443` |  |
| gateway.responseOverride.forbidden | object | `{"body":"{\"error\": \"Forbidden\"}","contentType":"application/json","enabled":true}` | Rewrite 403 responses with a custom body |
| gateway.responseOverride.unauthorized | object | `{"body":"{\"error\": \"Unauthorized\"}","contentType":"application/json","enabled":true}` | Rewrite 401 responses with a custom body |
| global.imagePullPolicy | string | `"Always"` |  |
| global.imagePullSecrets | list | `[]` | Image pull secrets applied to every Lamassu pod. |
| migrations.caToKms.enabled | bool | `false` | Enable the CA-to-KMS key migration pre-upgrade hook. Only needed when upgrading from a version prior to 3.7.0. |
| migrations.caToKms.image | string | `"ghcr.io/lamassuiot/lamassu-ca-to-kms-migration:dev-v4"` | Docker image for the CA-to-KMS migration tool |
| migrations.db.databases[0] | string | `"alerts"` |  |
| migrations.db.databases[1] | string | `"ca"` |  |
| migrations.db.databases[2] | string | `"va"` |  |
| migrations.db.databases[3] | string | `"devicemanager"` |  |
| migrations.db.databases[4] | string | `"dmsmanager"` |  |
| migrations.db.databases[5] | string | `"kms"` |  |
| migrations.db.image | string | `"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:dev-v4"` |  |
| nameOverride | string | `""` | Partially override the name used for release-scoped resources. |
| observability.enabled | bool | `false` | Enable OpenTelemetry instrumentation for all Lamassu services |
| observability.logs.basePath | string | `"/insert/opentelemetry/v1/logs"` | Base path for the Victoria Logs OTLP log ingestion endpoint |
| observability.logs.hostname | string | `"victoria-logs"` |  |
| observability.logs.port | int | `9428` | OTLP HTTP port exposed by Victoria Logs |
| observability.logs.scheme | string | `"http"` | Scheme for the Victoria Logs OTLP endpoint (http | https) |
| observability.routes | object | `{"jaeger":{"hostname":"jaeger","path":"/infra/jaeger","port":16686},"logs":{"hostname":"victoria-logs","path":"/infra/logs","port":9428},"traces":{"hostname":"victoria-traces","path":"/infra/traces","port":10428}}` | HTTP routes for the observability UIs exposed through the API Gateway |
| observability.routes.jaeger.hostname | string | `"jaeger"` | Backend service for the Jaeger query UI |
| observability.routes.jaeger.path | string | `"/infra/jaeger"` | Path prefix at which the Jaeger UI is exposed through the gateway (must match the Jaeger query base_path) |
| observability.routes.jaeger.port | int | `16686` | Backend port for the Jaeger query UI |
| observability.routes.logs.hostname | string | `"victoria-logs"` | Backend service for the Victoria Logs UI (vmui) |
| observability.routes.logs.path | string | `"/infra/logs"` | Path prefix at which Victoria Logs UI is exposed through the gateway |
| observability.routes.logs.port | int | `9428` | Backend port for the Victoria Logs UI |
| observability.routes.traces.hostname | string | `"victoria-traces"` | Backend service for the VictoriaTraces UI (vmui) |
| observability.routes.traces.path | string | `"/infra/traces"` | Path prefix at which VictoriaTraces UI is exposed through the gateway |
| observability.routes.traces.port | int | `10428` | Backend port for the VictoriaTraces UI |
| observability.traces.basePath | string | `""` | Base path for the OTLP traces ingestion endpoint (empty = standard /v1/traces) |
| observability.traces.hostname | string | `"otel-collector"` |  |
| observability.traces.port | int | `4318` | OTLP HTTP port exposed by the OTel Collector |
| observability.traces.scheme | string | `"http"` | Scheme for the OTLP traces endpoint (http | https) |
| postgres.hostname | string | `""` | Hostname for the PostgreSQL server |
| postgres.logLevel | string | `"info"` | Log level used by components that connect to PostgreSQL for their storage layer |
| postgres.password | string | `""` | Password to be used to authenticate with the PostgreSQL server |
| postgres.port | int | `5432` | Port for the PostgreSQL server |
| postgres.username | string | `""` | Username to be used to authenticate with the PostgreSQL server |
| serviceAccount.annotations | object | `{}` | Annotations added to the generated ServiceAccount. |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the Kubernetes API token into Lamassu pods. |
| serviceAccount.create | bool | `true` | Create a dedicated ServiceAccount for Lamassu workloads. |
| serviceAccount.name | string | `""` | ServiceAccount name. Defaults to the release-scoped chart name when create=true, otherwise default. |
| serviceDefaults | object | `{"affinity":{},"annotations":{},"autoscaling":{"enabled":false,"maxReplicas":5,"minReplicas":1,"targetCPUUtilizationPercentage":80,"targetMemoryUtilizationPercentage":80},"extraEnv":[],"imagePullSecrets":[],"labels":{},"livenessProbe":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":10,"path":"/health","periodSeconds":10,"successThreshold":1,"timeoutSeconds":5},"nodeSelector":{},"pdb":{"minAvailable":1},"podAnnotations":{},"podLabels":{},"podSecurityContext":{"seccompProfile":{"type":"RuntimeDefault"}},"port":8085,"readinessProbe":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":3,"path":"/health","periodSeconds":5,"successThreshold":1,"timeoutSeconds":5},"replicaCount":1,"resources":{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532},"startupProbe":{"enabled":true,"failureThreshold":60,"initialDelaySeconds":0,"path":"/health","periodSeconds":5,"successThreshold":1,"timeoutSeconds":5},"tolerations":[],"topologySpreadConstraints":[]}` | Generic defaults applied to every Lamassu service (ca, kms, va, ui, alerts, deviceManager, dmsManager, authz, wfx and aws connector instances). Any key here can be overridden per service under `services.<name>` — the per-service block is deep-merged on top of these defaults. Maps are merged key by key; lists (tolerations, topologySpreadConstraints, extraEnv, ...) replace the default wholesale. |
| serviceDefaults.affinity | object | `{}` | Pod affinity configuration. |
| serviceDefaults.annotations | object | `{}` | Extra annotations for the Deployment/StatefulSet |
| serviceDefaults.autoscaling.enabled | bool | `false` | Enable a HorizontalPodAutoscaler for the service |
| serviceDefaults.extraEnv | list | `[]` | Extra environment variables for the service container |
| serviceDefaults.imagePullSecrets | list | `[]` | Additional image pull secrets for this service. |
| serviceDefaults.labels | object | `{}` | Extra labels for the Deployment/StatefulSet and its pods (added next to the `app` label) |
| serviceDefaults.livenessProbe.enabled | bool | `true` | Enable the liveness probe. |
| serviceDefaults.nodeSelector | object | `{}` | Node selector for pod scheduling |
| serviceDefaults.pdb.minAvailable | int | `1` | minAvailable for PodDisruptionBudget. Only active when effective replica count > 1. |
| serviceDefaults.podAnnotations | object | `{}` | Extra annotations for the pods |
| serviceDefaults.podLabels | object | `{}` | Extra labels for the pods only |
| serviceDefaults.podSecurityContext | object | `{"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. |
| serviceDefaults.port | int | `8085` | HTTP port the service listens on (also used for Service, probes and gateway routes) |
| serviceDefaults.readinessProbe.enabled | bool | `true` | Enable the readiness probe. |
| serviceDefaults.replicaCount | int | `1` | Number of replicas. Ignored when autoscaling is enabled. |
| serviceDefaults.resources | object | `{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Container resource requests/limits. CPU and memory requests are required for utilization-based HPA metrics. |
| serviceDefaults.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Container-level security context. Owned distroless images run with their declared non-root UID/GID. Override per service (or per connector instance) when a custom image declares a different identity. |
| serviceDefaults.startupProbe.enabled | bool | `true` | Enable the startup probe so liveness checks do not kill slow-starting services. |
| serviceDefaults.tolerations | list | `[]` | Tolerations for pod scheduling |
| serviceDefaults.topologySpreadConstraints | list | `[]` | Topology spread constraints. |
| services.alerts.autoscaling.maxReplicas | int | `3` |  |
| services.alerts.image | string | `"ghcr.io/lamassuiot/lamassu-alerts:dev-v4"` | Docker image for the Alerts component |
| services.alerts.smtp_server.enable_ssl | bool | `true` | use TLS for the SMTP connection |
| services.alerts.smtp_server.from | string | `""` | email address to use as the sender of the alerts |
| services.alerts.smtp_server.host | string | `""` | SMTP server hostname |
| services.alerts.smtp_server.insecure | bool | `false` | skip TLS verification |
| services.alerts.smtp_server.password | string | `""` | SMTP server password |
| services.alerts.smtp_server.port | int | `25` | SMTP server port |
| services.alerts.smtp_server.username | string | `""` | SMTP server username |
| services.authz.bootstrap | list | `[{"auth_config":{"claims":[{"claim":"realm_access.roles","operator":"contains","value":"pki-admin"}]},"policy_ids":["lamassu.a6811b60-5f89-4ce7-badb-78ea234794d3","lamassu.7df018c1-3140-4a35-9067-2e7d6cec3ed2"],"principal_id":"oidc:pki-admin","principal_name":"PKI Admin","principal_type":"oidc"}]` | Bootstrap entries: list of {principal_id, principal_name, principal_type, auth_config, policy_ids} Seeded by the pre-install/pre-upgrade database Job, after the policies are preloaded. Creating a principal that already exists is a no-op, so these entries are safe to leave in place across upgrades.  The default grants full access to anyone whose OIDC token carries the "pki-admin" realm role. Without it a fresh install — and an upgrade from 3.8.0, where authz did not exist — comes up with no principals at all and nobody able to administer the PKI. Assign that role deliberately in the identity provider, or replace this entry with your own matching rule. |
| services.authz.credentials | object | `{}` | Map of schema name to database name for per-schema Postgres credentials. Uses global postgres credentials. e.g. credentials: { pki: { database: pki_db } } |
| services.authz.database | string | `"authz"` | PostgreSQL database name for authz principals, grants, and policies |
| services.authz.image | string | `"ghcr.io/lamassuiot/lamassu-authz:dev-v4"` | Docker image for the Authz connector component |
| services.authz.jwkUrl | string | `"http://auth-keycloak/auth/realms/lamassu/protocol/openid-connect/certs"` | JWKS endpoint used by authz to validate JWTs |
| services.ca.domains | list | `["dev.lamassu.io"]` | Domain to be used while signing/generating new CAs and certificates |
| services.ca.image | string | `"ghcr.io/lamassuiot/lamassu-ca:dev-v4"` | Docker image for the CA component |
| services.ca.monitoring.frequency | string | `"* * * * *"` | Frequency to check the CA's health status uses CRON syntax. Can also be specified at a "second" level by adding one extra term |
| services.connectors | object | `{}` | AWS connector instances keyed by stable connector ID. |
| services.deviceManager.image | string | `"ghcr.io/lamassuiot/lamassu-devmanager:dev-v4"` | Docker image for the Device Manager component |
| services.dmsManager.image | string | `"ghcr.io/lamassuiot/lamassu-dmsmanager:dev-v4"` | Docker image for the DMS Manager component |
| services.dmsManager.podSecurityContext.fsGroup | int | `65532` | Filesystem group that lets the cert-bundle init container and DMS container share generated certificates. |
| services.dmsManager.tlsInitContainer.image | string | `"busybox:1.37"` | Image for the container that builds the downstream CA bundle. |
| services.dmsManager.tlsInitContainer.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":false,"runAsGroup":65532,"runAsNonRoot":true,"runAsUser":65532}` | Security context for the container that builds the downstream CA bundle. |
| services.kms.args | list | `[]` | Optional arguments override for the KMS container |
| services.kms.autoscaling.maxReplicas | int | `3` |  |
| services.kms.command | list | `[]` | Optional command override for the KMS container |
| services.kms.cryptoEngines.defaultEngineID | string | `"filesystem-1"` | Default engine ID to be used for the KMS component |
| services.kms.cryptoEngines.engines[0].id | string | `"filesystem-1"` |  |
| services.kms.cryptoEngines.engines[0].metadata.prod-ready | string | `"false"` |  |
| services.kms.cryptoEngines.engines[0].storage_directory | string | `"/crypto/fs"` |  |
| services.kms.cryptoEngines.engines[0].type | string | `"filesystem"` |  |
| services.kms.image | string | `"ghcr.io/lamassuiot/lamassu-kms:dev-v4"` | Docker image for the KMS component. Replicas must stay at 1 while the filesystem crypto engine is configured (ReadWriteOnce PVC). |
| services.kms.pkcs11Modules | list | `[]` | Optional PKCS#11 modules to inject into KMS at runtime. Each entry runs a    short-lived init container that stages a module and optional config in a    shared volume mounted read-only into KMS. Fields: name (unique), image,    imagePullPolicy, securityContext, command, args, env, and mountPath. |
| services.kms.pkcs11Sidecar.args | list | `[]` | Arguments for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.command | list | `[]` | Command for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.enabled | bool | `false` | Requires Kubernetes 1.29+ due to native sidecar initContainer semantics. |
| services.kms.pkcs11Sidecar.env | list | `[]` | Extra environment variables for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.image | string | `""` | Sidecar image used to create the forwarded PKCS#11 socket |
| services.kms.pkcs11Sidecar.imagePullPolicy | string | `"IfNotPresent"` | Image pull policy for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.resources | object | `{}` | Resource requests and limits for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.securityContext | object | `{}` | Security context for the PKCS#11 sidecar. Defaults to KMS's own    securityContext (65532:65532); the forwarded mode-0660 Unix socket    is accessible to KMS through the pod's fsGroup. |
| services.kms.pkcs11Sidecar.socketDir | string | `"/run/p11-kit"` | Shared directory where the sidecar should create the PKCS#11 socket |
| services.kms.pkcs11Sidecar.volumeMounts | list | `[]` | Extra sidecar volume mounts, for example SSH key secrets |
| services.kms.pkcs11Sidecar.volumes | list | `[]` | Extra pod volumes needed by the PKCS#11 sidecar |
| services.ui.image | string | `"ghcr.io/lamassuiot/lamassu-ui:dev"` | Docker image for the UI component |
| services.ui.port | int | `8085` |  |
| services.va.autoscaling.maxReplicas | int | `3` |  |
| services.va.fileStore.id | string | `"local-1"` | Unique identifier for this storage engine instance |
| services.va.fileStore.local | object | `{"storageDirectory":"/data/crl"}` | Config for type=local. Maps to localfs.FilesystemEngineConfig (storage_directory) |
| services.va.fileStore.s3 | string | `nil` | Config for type=s3. Free-form map whose keys map directly to s3.AWSS3FilesystemConfig |
| services.va.fileStore.type | string | `"local"` | Storage backend type  Allowed values: local | s3 |
| services.va.image | string | `"ghcr.io/lamassuiot/lamassu-va:dev-v4"` | Docker image for the VA component. Replicas must stay at 1 while fileStore.type is "local" (ReadWriteOnce PVC). |
| services.va.job.crl.frequency | string | `"0 * * * *"` | Frequency to launch the CRL computation job |
| services.wfx.clientPort | int | `9080` | WFX southbound/client API port. |
| services.wfx.command | list | `["wfx"]` | WFX command override. The explicit command avoids conflicting flags baked into the image entrypoint. |
| services.wfx.enabled | bool | `true` | Enable the Siemens WFX workflow service |
| services.wfx.extraArgs | list | `[]` | Additional command line arguments for the WFX container. |
| services.wfx.extraEnv | list | `[]` |  |
| services.wfx.image | string | `"ghcr.io/siemens/wfx@sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678"` | Docker image for the WFX component, pinned by digest for immutability.    The image declares UID 65532, so it runs under the chart-wide 65532:65532,    non-root default (see SECURITY.md). |
| services.wfx.logs.format | string | `"json"` | WFX log format. |
| services.wfx.logs.level | string | `"debug"` | WFX log level. |
| services.wfx.managementPort | int | `9081` | WFX northbound/management API port. |
| services.wfx.postgres.database | string | `"wfx"` | PostgreSQL database name for WFX. |
| services.wfx.postgres.iamAuth.enabled | bool | `false` | Enable AWS RDS IAM authentication for PostgreSQL. |
| services.wfx.postgres.iamAuth.region | string | `""` | AWS region used for PostgreSQL IAM authentication. |
| services.wfx.postgres.sslmode | string | `"disable"` | PostgreSQL SSL mode for WFX. |
| services.wfx.routing.enabled | bool | `true` | Expose WFX through the Lamassu Gateway. |
| services.wfx.routing.nbiPath | string | `"/api/wfx/nbi/"` | Gateway path for the WFX northbound/management API. |
| services.wfx.routing.rewriteNbiPath | string | `"/api/wfx/"` | Explicit rewrite path for WFX northbound/management API. |
| services.wfx.routing.rewritePath | string | `"/api/wfx/"` | Path used when rewriting Gateway routes to WFX. |
| services.wfx.routing.rewriteSbiPath | string | `"/api/wfx/"` | Explicit rewrite path for WFX southbound/client API. |
| services.wfx.routing.sbiPath | string | `"/api/wfx/sbi/"` | Gateway path for the WFX southbound/client API. |
| tls.certManagerOptions.certSpec | object | `{"addresses":null,"commonName":"dev.lamassu.io","duration":"2160h","hostnames":["dev.lamassu.io"]}` | Duration for the certificate to be valid |
| tls.certManagerOptions.certSpec.duration | string | `"2160h"` | 2160h == 90days |
| tls.certManagerOptions.clusterIssuer | string | `""` | CertManager ClusterIssuer to use to sign the certificate for the API Gateway. |
| tls.certManagerOptions.issuer | string | `""` | CertManager Issuer to use to sign the certificate for the API Gateway. Ignored if `clusterIssuer` is set. If left empty, a self signed certificate will be used. |
| tls.externalOptions.secretName | string | `""` | Secret name for the TLS certificate to be used for the API Gateway (the secret at least must have `tls.crt` and `tls.key` keys) |
| tls.type | string | `"certManager"` | TLS certificate provider to use for the API Gateway. Allowed values are: `certManager`, `external` |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
