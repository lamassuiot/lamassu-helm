# softhsm

![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

SoftHSM with TCP and TLS proxy

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

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| hsm.label | string | `"lamassuHSM"` |  |
| hsm.pin | string | `"1234"` |  |
| hsm.slot | string | `"0"` |  |
| hsm.so_pin | string | `"5432"` |  |
| image | string | `"ghcr.io/lamassuiot/softhsm:latest"` |  |
| ssh.port | int | `22` | Service port for the internal SSH endpoint |
| ssh.authorizedKeys | string | `""` | Authorized public keys for the in-cluster SSH endpoint |
