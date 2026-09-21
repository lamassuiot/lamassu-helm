# softhsm

![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0.0](https://img.shields.io/badge/AppVersion-1.0.0-informational?style=flat-square)

SoftHSM with TCP and TLS proxy

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| hsm.slot | string | `"0"` | SoftHSM slot identifier used by the image entrypoint. |
| hsm.label | string | `"lamassuHSM"` |  |
| hsm.pin | string | `"1234"` |  |
| hsm.so_pin | string | `"5432"` |  |
| image | string | `"ghcr.io/lamassuiot/softhsm:latest"` |  |

