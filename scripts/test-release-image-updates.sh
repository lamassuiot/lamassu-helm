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
  '.services.connectors' \
  '.migrations.db.image' \
  '.migrations.caToKms.image'; do
  assert_path_exists "$path"
done

yq eval '.services.connectors."aws.primary" = {
  "type": "awsiot",
  "image": "ghcr.io/lamassuiot/lamassu-aws-connector:old"
}' -i "$fixture"
yq eval '.services.connectors."aws.secondary" = {
  "type": "awsiot",
  "image": "ghcr.io/lamassuiot/lamassu-aws-connector:old"
}' -i "$fixture"
yq eval '.services.connectors."emqx.primary" = {
  "type": "emqx",
  "image": "ghcr.io/example/emqx-connector:custom"
}' -i "$fixture"

ui_image_before=$(yq eval -r '.services.ui.image' "$fixture")
wfx_image_before=$(yq eval -r '.services.wfx.image' "$fixture")
connectivity_image_before=$(yq eval -r '.connectivityTest.image' "$fixture")

bash "$repo_root/scripts/update-release-images.sh" "$fixture" "$app_version"

lamassu_images=$(
  yq -o=json "$fixture" |
    python3 -c '
import json
import sys

document = json.load(sys.stdin)

def walk(value, path):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from walk(child, path + [key])
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from walk(child, path + [str(index)])
    elif (
        path[-1:] == ["image"]
        and path != ["services", "ui", "image"]
        and isinstance(value, str)
        and value.rsplit("/", 1)[-1].split("@", 1)[0].split(":", 1)[0].startswith("lamassu-")
    ):
        yield ".".join(path), value

walk_results = walk(document, [])
for path, value in walk_results:
    print("{}\t{}".format(path, value))
'
)

if [[ -z "$lamassu_images" ]]; then
  printf 'FAIL: no Lamassu-owned images found for release coverage\n' >&2
  exit 1
fi

while IFS=$'\t' read -r path image; do
  assert_equals \
    "Lamassu image ${path} uses app version" \
    "${image%:*}:${app_version}" \
    "$image"
done <<<"$lamassu_images"

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
assert_image 'Secondary AWS connector image uses app version' \
  '.services.connectors."aws.secondary".image' 'ghcr.io/lamassuiot/lamassu-aws-connector'
assert_equals \
  'Non-AWS connector image is preserved' \
  'ghcr.io/example/emqx-connector:custom' \
  "$(yq eval -r '.services.connectors."emqx.primary".image' "$fixture")"
assert_equals \
  'UI image is not changed by backend updates' \
  "$ui_image_before" \
  "$(yq eval -r '.services.ui.image' "$fixture")"
assert_equals \
  'WFX image is not changed by backend updates' \
  "$wfx_image_before" \
  "$(yq eval -r '.services.wfx.image' "$fixture")"
assert_equals \
  'Connectivity test image is not changed by backend updates' \
  "$connectivity_image_before" \
  "$(yq eval -r '.connectivityTest.image' "$fixture")"

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

backend_step=$(yq eval -o=json \
  '.jobs."generate-charts-changelog-update-versions".steps[] |
   select(.name == "Update Backend docker image version")' \
  "$repo_root/.github/workflows/release.yaml") || {
  printf 'FAIL: backend image update step not found in release.yaml\n' >&2
  exit 1
}
if [[ -z "$backend_step" ]]; then
  printf 'FAIL: backend image update step not found in release.yaml\n' >&2
  exit 1
fi
assert_contains \
  'release uses the shared image update script' \
  'scripts/update-release-images.sh' \
  "$backend_step"
assert_contains \
  'release has a backend shell command' \
  '"run":' \
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

ui_step=$(yq eval -o=json \
  '.jobs."generate-charts-changelog-update-versions".steps[] |
   select(.name == "Update UI docker image version")' \
  "$repo_root/.github/workflows/release.yaml") || {
  printf 'FAIL: UI image update step not found in release.yaml\n' >&2
  exit 1
}
if [[ -z "$ui_step" ]]; then
  printf 'FAIL: UI image update step not found in release.yaml\n' >&2
  exit 1
fi
assert_contains \
  'UI image updates are limited to lamassu' \
  "github.event.inputs.chart_to_release == 'lamassu'" \
  "$ui_step"
assert_contains \
  'UI release updates the UI image value' \
  '.services.ui.image' \
  "$ui_step"
assert_contains \
  'UI release passes the selected chart values file' \
  'charts/${{ github.event.inputs.chart_to_release }}/values.yaml' \
  "$ui_step"
