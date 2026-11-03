#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT

cp "$repo_root/charts/lamassu/values.yaml" "$fixture"

app_version="4.1.0"

assert_equals() {
  local description=$1
  local expected=$2
  local actual=$3

  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nexpected: %s\nactual: %s\n' \
      "$description" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$description"
}

assert_image() {
  local description=$1
  local path=$2
  local repository=$3

  assert_equals \
    "$description" \
    "${repository}:${app_version}" \
    "$(yq eval -r "$path" "$fixture")"
}

assert_path_exists() {
  local path=$1

  if [[ "$(yq eval "$path != null" "$fixture")" != "true" ]]; then
    printf 'FAIL: release path does not exist in charts/lamassu/values.yaml: %s\n' \
      "$path" >&2
    exit 1
  fi
  printf 'PASS: release path exists in charts/lamassu/values.yaml: %s\n' "$path"
}

assert_contains() {
  local description=$1
  local needle=$2
  local haystack=$3

  if ! grep -Fq "$needle" <<<"$haystack"; then
    printf 'FAIL: %s\nmissing: %s\n' "$description" "$needle" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$description"
}

assert_not_contains() {
  local description=$1
  local needle=$2
  local haystack=$3

  if grep -Fq "$needle" <<<"$haystack"; then
    printf 'FAIL: %s\nunexpected: %s\n' "$description" "$needle" >&2
    exit 1
  fi
  printf 'PASS: %s\n' "$description"
}

for path in \
  '.services.va.image' \
  '.services.ca.image' \
  '.services.deviceManager.image' \
  '.services.dmsManager.image' \
  '.services.alerts.image' \
  '.services.authz.image' \
  '.services.kms.image' \
  '.migrations.db.image' \
  '.migrations.caToKms.image'; do
  assert_path_exists "$path"
done

yq eval '.services.connectors = {
  "aws.primary": {
    "type": "awsiot",
    "image": "ghcr.io/lamassuiot/lamassu-aws-connector:old"
  },
  "emqx.primary": {
    "type": "emqx",
    "image": "ghcr.io/example/emqx-connector:custom"
  }
}' -i "$fixture"

bash "$repo_root/scripts/update-release-images.sh" "$fixture" "$app_version"

assert_image 'VA image uses app version' \
  '.services.va.image' 'ghcr.io/lamassuiot/lamassu-va'
assert_image 'CA image uses app version' \
  '.services.ca.image' 'ghcr.io/lamassuiot/lamassu-ca'
assert_image 'Device Manager image uses app version' \
  '.services.deviceManager.image' 'ghcr.io/lamassuiot/lamassu-devmanager'
assert_image 'DMS Manager image uses app version' \
  '.services.dmsManager.image' 'ghcr.io/lamassuiot/lamassu-dmsmanager'
assert_image 'Alerts image uses app version' \
  '.services.alerts.image' 'ghcr.io/lamassuiot/lamassu-alerts'
assert_image 'Authz image uses app version' \
  '.services.authz.image' 'ghcr.io/lamassuiot/lamassu-authz'
assert_image 'KMS image uses app version' \
  '.services.kms.image' 'ghcr.io/lamassuiot/lamassu-kms'
assert_image 'Database migration image uses app version' \
  '.migrations.db.image' 'ghcr.io/lamassuiot/lamassu-lamassu-db-migration'
assert_image 'CA-to-KMS migration image uses app version' \
  '.migrations.caToKms.image' 'ghcr.io/lamassuiot/lamassu-ca-to-kms-migration'
assert_image 'AWS connector image uses app version' \
  '.services.connectors."aws.primary".image' 'ghcr.io/lamassuiot/lamassu-aws-connector'
assert_equals \
  'Non-AWS connector image is preserved' \
  'ghcr.io/example/emqx-connector:custom' \
  "$(yq eval -r '.services.connectors."emqx.primary".image' "$fixture")"

ct_config=$(<"$repo_root/.github/ci/ct.yaml")
assert_not_contains \
  'ct.yaml does not pin a target branch' \
  $'target-branch:' \
  "$ct_config"

test_workflow=$(<"$repo_root/.github/workflows/test-chart.yaml")
assert_contains \
  'chart tests use the PR base branch' \
  "github.base_ref || 'main'" \
  "$test_workflow"

release_workflow=$(<"$repo_root/.github/workflows/release.yaml")
backend_step=$(grep -A6 -F 'name: Update Backend docker image version' <<<"$release_workflow") || {
  printf 'FAIL: backend image update step not found in release.yaml\n' >&2
  exit 1
}
assert_contains \
  'release uses the shared image update script' \
  'scripts/update-release-images.sh' \
  "$backend_step"
assert_contains \
  'release preserves multiline shell command' \
  'run: |' \
  "$backend_step"
assert_contains \
  'release passes the selected chart values file' \
  'charts/${{ github.event.inputs.chart_to_release }}/values.yaml' \
  "$backend_step"
assert_contains \
  'release passes app_version to image updates' \
  '${{ github.event.inputs.app_version }}' \
  "$backend_step"
assert_contains \
  'backend image updates are limited to lamassu' \
  "github.event.inputs.chart_to_release == 'lamassu'" \
  "$backend_step"

ui_step=$(grep -A4 -F 'name: Update UI docker image version' <<<"$release_workflow") || {
  printf 'FAIL: UI image update step not found in release.yaml\n' >&2
  exit 1
}
assert_contains \
  'UI image updates are limited to lamassu' \
  "github.event.inputs.chart_to_release == 'lamassu'" \
  "$ui_step"
