# softhsm

![Version: 1.3.0](https://img.shields.io/badge/Version-1.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

SoftHSM with TCP and TLS proxy, and optional Nitrokey NetHSM

## Usage

Install or upgrade:

```bash
helm upgrade --install hsm ./charts/softhsm -n lamassu --create-namespace --wait
```

Uninstall:

```bash
helm uninstall hsm -n lamassu
```

By default, this chart exposes PKCS#11 over TCP on port `5657`. With release name `hsm`, the in-cluster endpoint is `hsm-softhsm:5657`.

This chart always exposes an internal SSH port so a KMS sidecar can forward
`/run/p11-kit/pkcs11` from this pod over `ssh -L`.

For security, no default SSH public key is installed. Set `ssh.authorizedKeys`
to your own key(s) before using SSH tunneling.

## NetHSM

This chart can optionally deploy a [Nitrokey NetHSM](https://docs.nitrokey.com/nethsm/)
alongside SoftHSM. Enable it with `nethsm.enabled=true`:

```bash
helm upgrade --install hsm ./charts/softhsm -n lamassu --create-namespace --wait \
  --set nethsm.enabled=true
```

When enabled, the chart deploys a NetHSM `StatefulSet`, an HTTPS `Service`, and
a post-install/upgrade provisioning `Job` that adds an `Operator` user. With
release name `hsm`, its in-cluster endpoint is `hsm-nethsm:8443`.

Passphrases are stored in a `Secret`. The defaults are for local testing only;
override `nethsm.provision.*` for any real deployment. NetHSM requires
passphrases of 10-200 characters.

The `nitrokey/nethsm:testing` image is ephemeral. To retain NetHSM data across
restarts, enable `nethsm.persistence.enabled` and use a persistent image.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| softhsm.label | string | `"lamassuHSM"` |  |
| softhsm.pin | string | `"1234"` |  |
| softhsm.slot | string | `"0"` |  |
| softhsm.so_pin | string | `"5432"` |  |
| image | string | `"ghcr.io/lamassuiot/softhsm:latest"` |  |
| ssh.port | int | `22` | Service port for the internal SSH endpoint |
| ssh.authorizedKeys | string | `""` | Authorized public keys for the in-cluster SSH endpoint |
| nethsm.enabled | bool | `false` | Deploy a Nitrokey NetHSM alongside SoftHSM |
| nethsm.image | string | `"nitrokey/nethsm:testing"` | NetHSM container image |
| nethsm.port | int | `8443` | HTTPS REST API port exposed by NetHSM |
| nethsm.tokenLabel | string | `"LocalHSM"` | Token/slot label exposed by the p11nethsm PKCS#11 module |
| nethsm.persistence.enabled | bool | `false` | Persist the NetHSM `/data` directory |
| nethsm.persistence.size | string | `"2Gi"` | Size of the NetHSM data volume |
| nethsm.persistence.storageClassName | string | `""` | Storage class for the NetHSM data volume |
| nethsm.provision.image | string | `"curlimages/curl:8.11.0"` | Image used by the provisioning Job |
| nethsm.provision.unlockPassphrase | string | `"a0b1c2d3e4f5"` | Unlock passphrase set during provisioning |
| nethsm.provision.adminPassphrase | string | `"abcdefghijklm"` | Administrator passphrase set during provisioning |
| nethsm.provision.systemTime | string | `"2026-01-01T00:00:00Z"` | System time set during provisioning (UTC) |
| nethsm.provision.operator.userId | string | `"operator"` | Operator user ID |
| nethsm.provision.operator.realName | string | `"Lamassu Operator"` | Operator user real name |
| nethsm.provision.operator.passphrase | string | `"0123456789"` | Operator user passphrase |
