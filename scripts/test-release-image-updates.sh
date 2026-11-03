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
bash "$repo_root/scripts/update-release-images.sh" "$fixture" "$app_version"

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

assert_equals \
  'Authz image uses app version' \
  "ghcr.io/lamassuiot/lamassu-authz:${app_version}" \
  "$(yq eval -r '.services.authz.image' "$fixture")"
assert_equals \
  'AWS connector image uses app version' \
  "ghcr.io/lamassuiot/lamassu-aws-connector:${app_version}" \
  "$(yq eval -r '.services.connectors."aws.primary".image' "$fixture")"
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
backend_step=$(grep -A6 -F 'name: Update Backend docker image version' <<<"$release_workflow")
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

ui_step=$(grep -A4 -F 'name: Update UI docker image version' <<<"$release_workflow")
assert_contains \
  'UI image updates are limited to lamassu' \
  "github.event.inputs.chart_to_release == 'lamassu'" \
  "$ui_step"
