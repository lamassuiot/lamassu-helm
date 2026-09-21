# Security Engineering Blueprint

This document tracks the security posture of the Lamassu Helm chart. It is a
living engineering record for evidence, accepted exceptions, completed work,
and prioritized follow-up. It is not a vulnerability disclosure policy.

Last reviewed: 2026-09-21

## Status Legend

| Status | Meaning |
|---|---|
| Done | Implemented and verified in a rendered manifest or runtime test. |
| Partial | A mitigation exists, but the target design is not complete. |
| Todo | Confirmed gap with an agreed direction. |
| Deferred | Intentionally postponed; risk remains accepted for now. |
| Exception | A documented deviation required by the current image or workflow. |

## Principles

1. Each workload and special-purpose init container owns its runtime contract.
2. Image identity and chart identity must agree on a numeric UID and GID.
3. Generic defaults provide common hardening, not image-specific identity.
4. Root and added capabilities require a documented reason and exit condition.
5. Rendered manifests, image metadata, runtime behavior, and CI validation are
   evidence. Comments and defaults alone are not evidence.
6. Mutable tags are observations, not durable guarantees. Revalidate them or
   pin immutable tags or digests.

## Current Summary

| Workload | Current identity contract | Status | Security implication | Next action |
|---|---|---|---|---|
| Alerts | `65532:65532`, non-root | Done | Numeric identity is enforced and all capabilities are dropped. | Keep image and chart identity synchronized. |
| CA | `65532:65532`, non-root | Done | Numeric identity is enforced and all capabilities are dropped. | Keep image and chart identity synchronized. |
| Device Manager | `65532:65532`, non-root | Done | Numeric identity is enforced and all capabilities are dropped. | Keep image and chart identity synchronized. |
| AWS connector | Defaults to `65532:65532`, non-root; per-instance override supported | Done | Owned image is constrained without preventing custom-image identities. | Add a schema-level contract for overrides. |
| DMS Manager | Image non-root; shared `fsGroup: 65532` | Partial | Shared files are accessible, but the main container UID/GID is not explicitly pinned. | Set the main container to `65532:65532`; remove irrelevant `fsGroupChangePolicy` for `emptyDir`. |
| DMS TLS init | `65532:65532`, non-root | Done | Root-default toolbox image is safely overridden. | Rebuild toolbox with a numeric non-root `USER`. |
| Authz and authz init | `999:999`, non-root | Done | Named image user cannot bypass or confuse kubelet verification. | Publish the image with `USER 999:999`. |
| VA | Image non-root; no PVC `fsGroup` | Todo | Writable PVC behavior depends on storage-driver permissions. | Use `65532:65532`, `fsGroup: 65532`, and `OnRootMismatch` for local storage. |
| KMS | `65532:0`; `fsGroup: 0` when the PKCS#11 sidecar is enabled | Todo | Root-group membership broadens access and is a fragile volume-permission strategy. | Migrate to `65532:65532` and `fsGroup: 65532`, including existing PVC ownership. |
| UI | `65532:65532`, non-root, unprivileged port | Done | Rootless image removes the CHOWN/SETGID/SETUID exception and satisfies Restricted Pod Security. | Keep image and chart identity synchronized. |
| WFX | Image declares UID `65532`; chart sets `runAsNonRoot: false` | Todo | A mutable image can silently regress to root. | Pin an immutable image and enforce `65532:65532`, non-root. |
| DB migration binaries | Image declares UID `65532`; chart does not enforce it | Todo | A republished image could run migrations as root. | Add a migration-specific `65532:65532`, non-root contract. |
| PostgreSQL migration helpers | Run as root | Todo | Database credentials and shell logic run with unnecessary root privileges. | Run as `999:999`; PostgreSQL client tools were verified with this identity. |
| CA-to-KMS migration | Image non-root through shared defaults | Partial | UID/GID remain implicit and tied to mutable image metadata. | Add an explicit `65532:65532` migration contract. |
| Helm connectivity test | Root toolbox image | Todo | Test hooks unnecessarily run as root and fail Restricted policy. | Run as `65532:65532`, non-root. |
| PKCS#11 p11-kit module staging | Root with five narrowly restored capabilities | Exception | Runtime package installation cannot satisfy Restricted Pod Security. | Replace runtime `apt-get` with a prebuilt non-root module image. |

## Source Repositories

The images and workloads tracked in this document are built from these local
checkouts, which sit beside this Helm repository:

| Component | Path | Source of |
|---|---|---|
| Backend services | `/home/ubuntu/dev/lamassu/lamassuiot` | Go workspace (`backend/`, `core/`, `engines/`, `sdk/`, `shared/`) behind the Lamassu service images. |
| Dashboard | `/home/ubuntu/dev/lamassu/dashboard` | Next.js UI with its own `Dockerfile` and `nginx.conf`, which build the `lamassu-ui` image. |
| Templating reference | `/home/ubuntu/dev/helm-charts` | Standalone chart repository (`ct.yaml`, `lintconf.yaml`, chart-testing scripts) used as a chart-templating reference. |

## Verified Image Evidence

The following ARM64 image metadata was inspected locally on 2026-09-21. The
digest is included so later audits can distinguish an image change from a chart
change. The PostgreSQL entry is an AMD64 platform digest; its root default and
`postgres` account mapping were separately verified and are common to the image.

| Image | Declared `USER` | Observed digest |
|---|---:|---|
| `lamassu-alerts:dev-v4` | `65532` | `sha256:f11b2e8aa959167c0933878cb7969d0315700a7786509f9ac144f83eb3f043b4` |
| `lamassu-ca:dev-v4` | `65532` | `sha256:d188f63f304dc15ba46da33bef75de03437067a99c23a16a728c5b6438251452` |
| `lamassu-va:dev-v4` | `65532` | `sha256:267eede8f4edc3356eb463a28125e479ae70c3123172d23e174ba5f73247d1de` |
| `lamassu-devmanager:dev-v4` | `65532` | `sha256:606e503af75c6842f68efb4872bba1b244e1e8a38255c214883189e22a757d70` |
| `lamassu-dmsmanager:dev-v4` | `65532` | `sha256:d3849ab224bb9418907280775aa7299a0a46384f26225e4384fba183ca4d2715` |
| `lamassu-kms:dev-v4` | `65532` | `sha256:55ec20874d6ade17b2d761f6c36aa781261117eff803e85d10fa5af8a6893d5c` |
| `lamassu-authz:dev-v4` | `lamassu` (`999:999`) | `sha256:88959564b49bbeda622bbfb6142b98f5cce910072c98ff1e4bac8a2584f58f69` |
| `lamassu-ui:dev-v4` | `65532:65532` | Old rootless rebuild superseded by the `:dev` arm64 entry below; digest recorded when `dev-v4` is rebuilt. |
| `lamassu-ui:dev` (arm64) | `65532:65532` | Manifest digest `sha256:b183bcf52331d2190bdc074e0741cc885c0833d3535581f58cff82340b12277b`; pushed 2026-09-21; runtime-verified with `--cap-drop=ALL`, `no-new-privileges`. |
| `lamassu-lamassu-db-migration:dev-v4` | `65532` | `sha256:feb9c41131b3f19a7ddee12cc4bc248e74b41038e611ebd4327f1ea53b8b0f91` |
| `lamassu-aws-connector:dev-v4` | `65532` | `sha256:ad585a5120c8634eb18b72ee71dce6f8e45c70ddd54502f9b832b5bf5786ba01` |
| `lamassu-ca-to-kms-migration:dev-v4` | `65532` | `sha256:2c1262a7bc9504257d0d6e65be10b32ed07067b6c29202929806411446ad8b9f` |
| `toolbox:2.2.0` | root/empty | `sha256:464d86d83ec52abab587d1367de2603e51c46dc989641ecae460a2d68299b355` |
| `ghcr.io/siemens/wfx:latest` | `65532` | `sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678` |
| `postgres:18.4` | root/empty; `postgres=999:999` | `sha256:a02db8cac496f15b094798a38254f14d6e00741f709360e5e00bb6668ea31636` |

## Evidence Register

| ID | Evidence | Result |
|---|---|---|
| E-001 | Inspect exact image metadata with `docker image inspect` | Identity table above. |
| E-002 | Run Authz image and inspect `lamassu` account | Named user resolves to UID/GID `999:999`; chart now pins both. |
| E-003 | UI runtime log | nginx failed to `chown(/var/cache/nginx/client_temp, 101)` with all capabilities dropped. |
| E-004 | Run UI image with only `CHOWN`, `SETGID`, and `SETUID` | nginx remained running without startup errors. |
| E-005 | DMS kubelet event | Root-default toolbox image was rejected by inherited `runAsNonRoot: true`. |
| E-006 | Run toolbox as `65532:65532` | Shell and required certificate utilities worked as non-root. |
| E-007 | KMS kubelet event | p11-kit module had the invalid combination `runAsUser: 0` and `runAsNonRoot: true`. |
| E-008 | Reproduce p11-kit installation in `debian:12-slim` | Installation succeeds with root, `no-new-privileges`, `drop: ALL`, and only `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETGID`, `SETUID` restored. |
| E-009 | Run PostgreSQL client utilities as `999:999` | `psql`, `pg_dump`, and writes to `/tmp` succeed without root. |
| E-010 | Render and validate the chart | Helm lint and kubeconform pass for default, contract, current fast-lane, and HSM configurations used during this review. |
| E-011 | Inspect namespace labels | `lamassu-dev` currently has no Pod Security Admission enforcement, audit, or warning labels. |
| E-012 | Run `ghcr.io/lamassuiot/lamassu-ui:dev` with `--cap-drop=ALL` and `no-new-privileges` | nginx served HTTP 200 on 8085, `config.js` was stamped from env, and `id` reported `uid=65532 gid=65532`. |

## Completed Work

- [x] Set `RuntimeDefault` seccomp at pod level for chart workloads.
- [x] Disable privilege escalation and drop all capabilities by default.
- [x] Disable automatic ServiceAccount token mounting by default.
- [x] Give Alerts, CA, and Device Manager explicit `65532:65532` contracts.
- [x] Give AWS connectors a `65532:65532` default with per-instance overrides.
- [x] Pin Authz and its migration init container to `999:999`.
- [x] Run the DMS TLS init container as `65532:65532` with `fsGroup: 65532`.
- [x] Limit the current root UI image to its three verified capabilities.
- [x] Separate PKCS#11 module-init security from the KMS application contract.
- [x] Limit the p11-kit root installer to five verified capabilities.
- [x] Validate the ARM64 architecture of current Lamassu service images.

## Prioritized Work

### P0 - Deferred By Decision

- [ ] **Deferred:** move credentials currently rendered into ConfigMaps to
  Secrets or external secret references. Do not mark complete until templates,
  upgrade behavior, and redaction tests are implemented.

### P1 - Identity And Admission

- [x] Build a rootless UI image running as `65532:65532` on an unprivileged
  port; publish with `docker buildx build --platform linux/amd64,linux/arm64
  --push` for multi-architecture availability.
- [ ] Enforce `65532:65532` and `runAsNonRoot: true` for WFX; stop using `latest`.
- [ ] Run database migration images as `65532:65532`, non-root.
- [ ] Run PostgreSQL migration helpers as `999:999`, non-root.
- [ ] Run the Helm connectivity test toolbox as `65532:65532`, non-root.
- [ ] Change KMS and its PKCS#11 sidecar from GID `0` to GID `65532`.
- [ ] Add explicit `65532:65532` contracts to DMS, VA, and CA-to-KMS.
- [ ] Enable Pod Security Admission gradually: `enforce=baseline`, then
  `warn=restricted` and `audit=restricted`; enforce Restricted only after all
  documented exceptions are removed.

### P2 - Filesystems And Supply Chain

- [ ] Add `fsGroup: 65532` and `OnRootMismatch` to KMS and VA when they use PVCs.
- [ ] Test `readOnlyRootFilesystem: true` for every service and provide explicit
  writable mounts for `/tmp`, caches, sockets, generated config, and state.
- [ ] Replace runtime `apt-get` in the p11-kit init container with a prebuilt,
  non-root, digest-pinned image.
- [ ] Replace mutable production tags with immutable versions or digests.
- [ ] Validate security-context fields and UID/GID ranges in `values.schema.json`.
- [ ] Add CI assertions for effective UID/GID, non-root guards, capabilities,
  seccomp, privilege escalation, and ServiceAccount token mounting.
- [ ] Evaluate `supplementalGroupsPolicy: Strict` only after the chart's minimum
  Kubernetes version supports it.

## Exception Register

| Exception | Current justification | Allowed scope | Exit condition |
|---|---|---|---|
| p11-kit staging runs as root and adds five capabilities | Online fast-lane installs `p11-kit-modules` into a transient Debian container. | `kms-pkcs11-module-p11-kit-client` init container only. | Prebuilt module image contains the library and dependencies and can copy them as non-root. |
| KMS and sidecar use primary/supplementary GID `0` | Current socket and PVC permissions were designed around the root group. | KMS pod only. | Ownership migration and `fsGroup: 65532` are verified on existing and fresh volumes. |

## Target Runtime Contracts

| Image class | Target UID:GID | Required controls |
|---|---:|---|
| Owned distroless Go services | `65532:65532` | `runAsNonRoot`, no privilege escalation, drop all capabilities, `RuntimeDefault` seccomp. |
| Authz | `999:999` | Same controls; image should declare the numeric identity. |
| PostgreSQL client-only hooks | `999:999` | Same controls; writable `/tmp` only. |
| Toolbox init/test containers | `65532:65532` | Same controls; explicit writable shared volume where needed. |
| Rootless UI | `65532:65532` | Same controls; unprivileged port and `/tmp`-based runtime paths. |
| User-provided PKCS#11 modules | Explicit per module | Numeric UID/GID and non-root intent must be supplied with the module definition. |

## Reproducible Validation

Run these checks after any image, workload, security-context, volume, or
fast-lane change:

```bash
helm lint charts/lamassu
helm lint charts/lamassu -f charts/lamassu/ci/template-contract-values.yaml
helm lint charts/lamassu -f charts/lamassu/ci/pkcs11-incluster-hsm-values.yaml --kube-version 1.29.0
helm template lamassu charts/lamassu --namespace lamassu-test --output-dir /tmp/lamassu-rendered
kubeconform -strict -summary -ignore-missing-schemas -kubernetes-version 1.29.0 /tmp/lamassu-rendered/lamassu/templates
bash -n scripts/lamassu-fast-lane.sh
git diff --check
```

For runtime evidence, capture the exact image digest and effective manifest:

```bash
docker image inspect IMAGE --format '{{.Architecture}} {{.Config.User}} {{json .RepoDigests}}'
kubectl get pod POD -n NAMESPACE -o yaml
kubectl get events -n NAMESPACE --sort-by=.lastTimestamp
```

Never store credentials, Secret data, private keys, or unredacted generated
values files as evidence in this repository.

## Definition Of Done

A security item is Done only when:

1. The chart renders the intended effective contract.
2. Helm lint and schema validation pass.
3. Kubeconform reports no invalid built-in resources.
4. The container starts under the intended UID/GID and capabilities.
5. Writable volume behavior is verified on fresh and existing storage when
   ownership changes are involved.
6. Generated documentation and fast-lane output agree with the chart.
7. The evidence and exception registers above are updated.

## Change Log

- 2026-09-21: Pinned the Envoy Gateway `envoyService` to
  `externalTrafficPolicy: Cluster` in the chart's EnvoyProxy template. Envoy
  Gateway defaults to `Local`, which silently dropped traffic entering any
  node without a local proxy pod; the lab gateway VIP became unreachable from
  multi-node ingress. Verified externally over the lab tunnel after the change.

- 2026-09-21: Rebuilt the UI as a rootless `65532:65532` nginx image on port
  8085; the chart now inherits the hardened `serviceDefaults`, removing the
  CHOWN/SETGID/SETUID exception. Arm64 image pushed to
  `ghcr.io/lamassuiot/lamassu-ui:dev` and runtime-verified with all
  capabilities dropped.
- 2026-09-21: Initial blueprint created from the UID/GID, image architecture,
  DMS init, UI nginx, migration, AWS connector, and KMS PKCS#11 investigations.
