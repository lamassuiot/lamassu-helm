# Lamassu Helm Charts

This repository contains Helm charts for deploying and managing Lamassu services within Kubernetes environments. Lamassu is an IoT device identity management platform that provides certificate management and device lifecycle management capabilities.

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