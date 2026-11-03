#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT

cat >"$fixture" <<'YAML'
services:
  authz:
    image: ghcr.io/lamassuiot/lamassu-authz:old
  connectors:
    aws.primary:
      type: awsiot
      image: ghcr.io/lamassuiot/lamassu-aws-connector:old
    emqx.primary:
      type: emqx
      image: ghcr.io/example/emqx-connector:custom
YAML

app_version="4.1.0"
yq eval ".services.authz.image = \"ghcr.io/lamassuiot/lamassu-authz:${app_version}\"" \
  -i "$fixture"
yq eval "(.services.connectors[] | select(.type == \"awsiot\") | .image) = \"ghcr.io/lamassuiot/lamassu-aws-connector:${app_version}\"" \
  -i "$fixture"

test "$(yq eval -r '.services.authz.image' "$fixture")" = \
  "ghcr.io/lamassuiot/lamassu-authz:${app_version}"
test "$(yq eval -r '.services.connectors."aws.primary".image' "$fixture")" = \
  "ghcr.io/lamassuiot/lamassu-aws-connector:${app_version}"
test "$(yq eval -r '.services.connectors."emqx.primary".image' "$fixture")" = \
  "ghcr.io/example/emqx-connector:custom"

! grep -q '^target-branch:' "$repo_root/.github/ci/ct.yaml"
grep -Fq 'github.base_ref || '\''main'\''' \
  "$repo_root/.github/workflows/test-chart.yaml"
