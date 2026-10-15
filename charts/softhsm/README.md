# softhsm

![Version: 1.4.0](https://img.shields.io/badge/Version-1.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

SoftHSM exposed over a p11-kit Unix socket forwarded via SSH, and optional Nitrokey NetHSM

## Usage

Install or upgrade:

```bash
helm upgrade --install hsm ./charts/softhsm -n lamassu --create-namespace --wait \
  --set-string softhsm.pin="<user-pin>" \
  --set-string softhsm.so_pin="<so-pin>" \
  --set-string ssh.authorizedKeys="$(cat ~/.ssh/id_ed25519.pub)"
```

The chart ships no default PINs: `softhsm.pin` and `softhsm.so_pin` are
required and rendering fails if either is empty.

Uninstall:

```bash
helm uninstall hsm -n lamassu
```

This chart exposes PKCS#11 over a Unix socket at `/run/p11-kit/pkcs11` inside
the pod. It always exposes an internal SSH port so a KMS sidecar can forward
that socket from this pod over `ssh -L` (see `charts/lamassu`'s
`services.kms.pkcs11Sidecar`). There is no directly reachable TCP PKCS#11
endpoint.

For security, no default SSH public key is installed. Set `ssh.authorizedKeys`
to your own key(s) before using SSH tunneling.

## NetHSM

This chart can optionally deploy a [Nitrokey NetHSM](https://docs.nitrokey.com/nethsm/)
alongside SoftHSM. Enable it with `nethsm.enabled=true`:

```bash
helm upgrade --install hsm ./charts/softhsm -n lamassu --create-namespace --wait \
  --set-string softhsm.pin="<user-pin>" \
  --set-string softhsm.so_pin="<so-pin>" \
  --set nethsm.enabled=true \
  --set-string nethsm.provision.unlockPassphrase="<unlock-passphrase>" \
  --set-string nethsm.provision.adminPassphrase="<admin-passphrase>" \
  --set-string nethsm.provision.operator.passphrase="<operator-passphrase>"
```

When enabled, the chart deploys a NetHSM `StatefulSet`, an HTTPS `Service`, and
a post-install/upgrade provisioning `Job` that adds an `Operator` user. With
release name `hsm`, its in-cluster endpoint is `hsm-nethsm:8443`.

Passphrases are stored in a `Secret`. The chart ships no default passphrases:
`nethsm.provision.unlockPassphrase`, `nethsm.provision.adminPassphrase` and
`nethsm.provision.operator.passphrase` must each be set to 10-200 characters
when `nethsm.enabled=true`, otherwise rendering fails.

The `nitrokey/nethsm:testing` image is ephemeral. To retain NetHSM data across
restarts, enable `nethsm.persistence.enabled` and use a persistent image.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| softhsm.label | string | `"lamassuHSM"` |  |
| softhsm.pin | string | `""` | User PIN for the SoftHSM token. Required |
| softhsm.slot | string | `"0"` |  |
| softhsm.so_pin | string | `""` | Security Officer PIN for the SoftHSM token. Required |
| image | string | `"ghcr.io/lamassuiot/softhsm:dev"` |  |
| ssh.port | int | `22` | Service port for the internal SSH endpoint |
| ssh.authorizedKeys | string | `""` | Authorized public keys for the in-cluster SSH endpoint |
| nethsm.enabled | bool | `false` | Deploy a Nitrokey NetHSM alongside SoftHSM |
| nethsm.image | string | `"nitrokey/nethsm:testing"` | NetHSM container image |
| nethsm.port | int | `8443` | HTTPS REST API port exposed by NetHSM |
| nethsm.tokenLabel | string | `"LocalHSM"` | Token/slot label exposed by the p11nethsm PKCS#11 module |
| nethsm.persistence.enabled | bool | `false` | Persist the NetHSM `/data` directory |
| nethsm.persistence.size | string | `"2Gi"` | Size of the NetHSM data volume |
| nethsm.persistence.storageClassName | string | `""` | Storage class for the NetHSM data volume. Empty uses the cluster's default StorageClass |
| nethsm.provision.image | string | `"curlimages/curl:8.11.0"` | Image used by the provisioning Job |
| nethsm.provision.unlockPassphrase | string | `""` | Unlock passphrase set during provisioning (10-200 characters). Required when `nethsm.enabled=true` |
| nethsm.provision.adminPassphrase | string | `""` | Administrator passphrase set during provisioning (10-200 characters). Required when `nethsm.enabled=true` |
| nethsm.provision.systemTime | string | `"2026-01-01T00:00:00Z"` | System time set during provisioning (UTC) |
| nethsm.provision.operator.userId | string | `"operator"` | Operator user ID |
| nethsm.provision.operator.realName | string | `"Lamassu Operator"` | Operator user real name |
| nethsm.provision.operator.passphrase | string | `""` | Operator user passphrase (10-200 characters). Required when `nethsm.enabled=true` |
