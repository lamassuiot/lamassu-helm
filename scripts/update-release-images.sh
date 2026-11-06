#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <values-file> <app-version>" >&2
  exit 2
fi

values_file=$1
app_version=$2

yq eval ".services.va.image = \"ghcr.io/lamassuiot/lamassu-va:${app_version}\"" -i "$values_file"
yq eval ".services.ca.image = \"ghcr.io/lamassuiot/lamassu-ca:${app_version}\"" -i "$values_file"
yq eval ".services.deviceManager.image = \"ghcr.io/lamassuiot/lamassu-devmanager:${app_version}\"" -i "$values_file"
yq eval ".services.dmsManager.image = \"ghcr.io/lamassuiot/lamassu-dmsmanager:${app_version}\"" -i "$values_file"
yq eval ".services.alerts.image = \"ghcr.io/lamassuiot/lamassu-alerts:${app_version}\"" -i "$values_file"
yq eval ".services.authz.image = \"ghcr.io/lamassuiot/lamassu-authz:${app_version}\"" -i "$values_file"
yq eval ".services.kms.image = \"ghcr.io/lamassuiot/lamassu-kms:${app_version}\"" -i "$values_file"
yq eval "(.services.connectors[] | select(.type == \"awsiot\") | .image) = \"ghcr.io/lamassuiot/lamassu-aws-connector:${app_version}\"" -i "$values_file"
yq eval ".migrations.db.image = \"ghcr.io/lamassuiot/lamassu-lamassu-db-migration:${app_version}\"" -i "$values_file"
yq eval ".migrations.caToKms.image = \"ghcr.io/lamassuiot/lamassu-ca-to-kms-migration:${app_version}\"" -i "$values_file"
