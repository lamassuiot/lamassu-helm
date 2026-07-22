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
| auth.externalAuthorization.enabled | bool | `true` | Protect routes labeled `auth=external` with Envoy Gateway external authorization |
| auth.externalAuthorization.serviceName | string | `"authz"` | Kubernetes Service name for the external authorization endpoint |
| auth.externalAuthorization.servicePort | int | `8085` | Kubernetes Service port for the external authorization endpoint |
| auth.externalAuthorization.path | string | `"/v1/ext_authz/check"` | HTTP path that replaces the original request path for the external authorization check. Requires Envoy Gateway v1.8.0+ |
| auth.externalAuthorization.failOpen | bool | `false` | Allow traffic when the external authorization service cannot be reached |
| **Service Images** | | | |
| services.ui.image | string | `"ghcr.io/lamassuiot/lamassu-ui:4.3.0"` | Docker image for UI component |
| services.ca.image | string | `"ghcr.io/lamassuiot/lamassu-ca:3.8.0"` | Docker image for CA component |
| services.va.image | string | `"ghcr.io/lamassuiot/lamassu-va:3.8.0"` | Docker image for VA component |
| services.kms.image | string | `"ghcr.io/lamassuiot/lamassu-kms:3.8.0"` | Docker image for KMS component |
| services.deviceManager.image | string | `"ghcr.io/lamassuiot/lamassu-devmanager:3.8.0"` | Docker image for Device Manager component |
| services.dmsManager.image | string | `"ghcr.io/lamassuiot/lamassu-dmsmanager:3.8.0"` | Docker image for DMS Manager component |
| services.authz.jwkUrl | string | `"http://auth-keycloak/auth/realms/lamassu/protocol/openid-connect/certs"` | JWKS endpoint used by authz to validate JWTs |
| services.wfx.enabled | bool | `true` | Enable the Siemens WFX workflow service |
| services.wfx.image | string | `"ghcr.io/siemens/wfx:latest"` | Docker image for WFX component |
| services.wfx.replicas | int | `1` | Number of WFX replicas |
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
| services.alerts.image | string | `"ghcr.io/lamassuiot/lamassu-alerts:3.8.0"` | Docker image for Alerts component |
| **Replicas & Autoscaling** | | | |
| services.\<svc\>.replicaCount | int | `1` | Number of replicas for the service. Ignored when `autoscaling.enabled` is `true`. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.autoscaling.enabled | bool | `false` | Enable HorizontalPodAutoscaler for the service. When `true`, the `replicas` field is omitted from the Deployment/StatefulSet and managed by the HPA |
| services.\<svc\>.autoscaling.minReplicas | int | `1` | Minimum number of replicas for the HPA |
| services.\<svc\>.autoscaling.maxReplicas | int | `5` | Maximum number of replicas for the HPA |
| services.\<svc\>.autoscaling.targetCPUUtilizationPercentage | int | `80` | Target CPU utilization percentage for HPA scaling |
| services.\<svc\>.autoscaling.targetMemoryUtilizationPercentage | int | `80` | Target memory utilization percentage for HPA scaling |
| **PodDisruptionBudget** | | | |
| services.\<svc\>.pdb.minAvailable | int | `1` | Minimum number of pods that must remain available during node drains and rolling upgrades. PDB is only created when the effective replica count is greater than 1. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| **Pod Affinity & Topology Spread** | | | |
| services.\<svc\>.affinity | object | `{}` | Pod affinity override. `{}` uses the chart default: soft (`preferredDuringScheduling`) pod anti-affinity on `kubernetes.io/hostname`, spreading replicas across nodes. Provide a full [affinity spec](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity) to replace it. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
| services.\<svc\>.topologySpreadConstraints | list | `[]` | Topology spread constraints override. `[]` uses the chart defaults: two `ScheduleAnyway` constraints spreading pods across `topology.kubernetes.io/zone` and `kubernetes.io/hostname`. Provide a list of [TopologySpreadConstraint](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) objects to replace them. Applies to: `ui`, `ca`, `va`, `kms`, `deviceManager`, `dmsManager`, `alerts` |
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
| services.kms.command | list | `[]` | Optional command override for the KMS container, useful for waiting on a forwarded PKCS#11 socket before launch |
| services.kms.args | list | `[]` | Optional arguments override for the KMS container |
| services.kms.pkcs11Sidecar.enabled | bool | `false` | Deploy a sidecar that creates a PKCS#11 socket on a shared volume for KMS. Requires Kubernetes 1.29+ |
| services.kms.pkcs11Sidecar.image | string | `""` | Sidecar image used to create the forwarded PKCS#11 socket |
| services.kms.pkcs11Sidecar.imagePullPolicy | string | `"IfNotPresent"` | Image pull policy for the PKCS#11 sidecar |
| services.kms.pkcs11Sidecar.securityContext | object | `{runAsNonRoot: true, runAsUser: 65532, runAsGroup: 0}` | Security context that keeps the forwarded mode-0600 socket accessible to KMS |
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
| **Toolbox & Migrations** | | | |
| toolbox.image | string | `"ghcr.io/lamassuiot/toolbox:2.2.0"` | Docker image for toolbox utility |
| migrations.db.image | string | `"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:3.8.0"` | Docker image for database migrations |
| migrations.db.databases | list | `["alerts", "ca", "va", "devicemanager", "dmsmanager", "kms"]` | List of databases to migrate |
| migrations.caToKms.image | string | `"ghcr.io/lamassuiot/lamassu-ca-to-kms-migration:3.8.0"` | Docker image for the CA-to-KMS migration tool |

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

Example values: [charts/lamassu/ci/pkcs11-incluster-hsm-values.yaml](/home/ubuntu/dev/lamassu/lamassu-helm/charts/lamassu/ci/pkcs11-incluster-hsm-values.yaml)

Build the proxy image from [ci/softhsm/proxy.dockerfile](/home/ubuntu/dev/lamassu/lamassu-helm/ci/softhsm/proxy.dockerfile:1), then configure:

```yaml
services:
  kms:
    command:
      - /bin/sh
    args:
      - -ec
      - |
        until [ -S /run/p11-kit/pkcs11 ]; do
          echo "Waiting for PKCS#11 SSH tunnel..."
          sleep 1
        done
        exec /bin/lamassu-kms
    pkcs11Sidecar:
      enabled: true
      image: ghcr.io/lamassuiot/p11-kit-ssh-sidecar:latest
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
    cryptoEngines:
      defaultEngineID: pkcs11-1
      engines:
        - id: pkcs11-1
          type: pkcs11
          token: "your-token-label"
          pin: "1234"
          module_path: "/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so"
          module_extra_options:
            env:
              P11_KIT_SERVER_ADDRESS: "unix:path=/run/p11-kit/pkcs11"
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
- The Lamassu KMS image must already contain `p11-kit-client.so`.
- If KMS starts before the tunnel is ready, use `services.kms.command/args`
  to wait until `/run/p11-kit/pkcs11` exists before launching the real binary.
