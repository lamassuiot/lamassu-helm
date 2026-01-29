# Lamassu Helm Charts

This repository contains Helm charts for deploying and managing Lamassu services within Kubernetes environments. Lamassu is an IoT device identity management platform that provides certificate management and device lifecycle management capabilities.

## Version History

This table shows the relationship between Helm chart versions, application versions, and the Docker image versions used for each component.

### Version 3.x Series

| Helm Chart | App Version | UI Image | Backend Images (CA/VA/DevMgr/DMS/Alerts) | KMS Image | Notes |
|------------|-------------|----------|-------------------------------------------|-----------|-------|
| 3.7.0 | 3.7.0 | 4.2.0 | 3.7.0 | 3.7.0 | **NEW**: KMS service introduced as first-class service |
| 3.6.1 | 3.6.1 | 4.1.1 | 3.6.1 | N/A | Latest stable release on main branch |
| 3.6.0 | 3.6.0 | 4.1.0 | 3.6.0 | N/A | |
| 3.5.2 | 3.5.2 | 4.0.5 | 3.5.2 | N/A | |
| 3.5.1 | 3.5.1 | 4.0.3 | 3.5.1 | N/A | |
| 3.5.0 | 3.5.0 | 4.0.2 | 3.5.0 | N/A | |
| 3.4.0 | 3.4.0 | 3.4.0 | 3.4.0 | N/A | |
| 3.3.1 | 3.3.1 | 3.3.1 | 3.3.1 | N/A | Multiple OIDC providers support |
| 3.3.0 | 3.3.0 | 3.3.0 | 3.3.0 | N/A | **MAJOR**: Migration from Ingress to Envoy Gateway |
| 3.2.1 | 3.2.2 | 3.2.1 | 3.2.2 | N/A | Automatic DB migrations introduced |
| 3.2.0 | 3.2.2 | 3.2.1 | 3.2.2 | N/A | Crypto engines restructure |
| 3.1.1 | 2.8.0 | 3.1.0 | 2.8.0 | N/A | |
| 3.1.0 | 2.8.0 | 3.1.0 | 2.8.0 | N/A | |
| 3.0.0 | 2.7.0 | 3.0.0 | 2.7.0 | N/A | **MAJOR**: First 3.x release |

**Component Legend:**
- **UI Image**: Frontend web application (`lamassu-ui`)
- **Backend Images**: Core services with synchronized versions:
  - `lamassu-ca`: Certificate Authority service
  - `lamassu-va`: Validation Authority service  
  - `lamassu-devmanager`: Device Manager service
  - `lamassu-dmsmanager`: DMS Manager service
  - `lamassu-alerts`: Alerts service
- **KMS Image**: Key Management Service (`lamassu-kms`) - introduced in 3.7.0

### Migration Guides

For detailed migration instructions between versions, see the CHANGELOG directory:
- [3.3.2 → 3.7.0](charts/lamassu/CHANGELOG/3.3.2->3.7.0.md) - KMS service introduction
- [3.3.0 → 3.3.1](charts/lamassu/CHANGELOG/3.3.0->3.3.1.md) - Multiple OIDC providers
- [3.2.X → 3.3.0](charts/lamassu/CHANGELOG/3.2.X->3.3.0.md) - Ingress to Envoy Gateway migration
- [3.0.X → 3.2.X](charts/lamassu/CHANGELOG/3.0.X->3.2.X.md) - Crypto engines restructure

## Repository Structure

```
.
├── charts/                # Helm charts
│   ├── lamassu/           # Lamassu main chart
│   └── softhsm/           # SoftHSM chart for HSM emulation
├── ci/                    # CI/CD related resources
└── scripts/               # Lamassu fast lane deployment script
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- cert-manager v1.14.0+ (for TLS certificate management)
- Envoy Gateway v1.3.0+ (for API Gateway functionality)

## Installation

### Option 1: Standard Installation

1. Add the Lamassu Helm repository:

```bash
helm repo add lamassu https://lamassuiot.github.io/lamassu-helm
helm repo update
```

2. Install the Lamassu chart:

```bash
helm install lamassu lamassu/lamassu -n lamassu --create-namespace
```

### Option 2: Fast Lane Installation

For quick deployment, you can use the provided fast lane script:

```bash
./scripts/lamassu-fast-lane.sh
```

## Configuration

### Basic Configuration

The main configuration file for Lamassu is `lamassu.yaml`. You can create your own configuration file based on this template and customize it according to your needs:

```bash
helm install lamassu lamassu/lamassu -f your-values.yaml -n lamassu --create-namespace
```

### External Dependencies

Lamassu requires the following external services:

- PostgreSQL database
- Keycloak for authentication
- RabbitMQ for messaging

You can deploy these dependencies independently or let the Lamassu chart handle them.

## Upgrading

### Version Migration Guides

For detailed migration steps, please refer to the `/charts/lamassu/CHANGELOG` folder in this repository.

**Important Note:** Starting from version 3.x, Lamassu uses Envoy Gateway instead of Ingress for routing traffic. See the migration guides for details.

## Development

### Testing Charts Locally

```bash
# Lint the chart
helm lint charts/lamassu

# Test installation with dry run
helm install lamassu charts/lamassu --dry-run --debug
```

### CI/CD

This repository uses GitHub Actions for CI/CD:

- `.github/workflows/test-chart.yaml`: Tests and validates the Helm charts
- `.github/workflows/release.yaml`: Handles the release process
- `test-fast-lane.yaml`: Tests the fast lane deployment script


## License

This project is licensed under the Mozilla Public License 2.0 - see the `LICENSE` file for details.

## Support

For issues, questions, or contributions, please open an issue or pull request in this repository.