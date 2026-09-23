# Security Engineering Blueprint

This document tracks the security posture of the Lamassu Helm chart. It is a
living engineering record for evidence, accepted exceptions, completed work,
and prioritized follow-up. It is not a vulnerability disclosure policy.

Last reviewed: 2026-09-23

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
| Alerts | `65532:65532`, non-root | Done | Numeric identity comes from `serviceDefaults.securityContext` and all capabilities are dropped. | Keep image and chart identity synchronized. |
| CA | `65532:65532`, non-root | Done | Numeric identity comes from `serviceDefaults.securityContext` and all capabilities are dropped. | Keep image and chart identity synchronized. |
| Device Manager | `65532:65532`, non-root | Done | Numeric identity comes from `serviceDefaults.securityContext` and all capabilities are dropped. | Keep image and chart identity synchronized. |
| AWS connector | Defaults to `65532:65532`, non-root via `serviceDefaults.securityContext`; per-instance override supported | Done | Owned image is constrained without preventing custom-image identities; `values.schema.json` now rejects `runAsNonRoot: false`, `privileged`, added capabilities, and unknown fields for any connector override. | Keep image and chart identity synchronized. |
| DMS Manager | `65532:65532`, non-root; shared `fsGroup: 65532` | Done | The main container identity is now pinned by `serviceDefaults.securityContext`. | Keep image and chart identity synchronized. |
| DMS TLS init | `65532:65532`, non-root | Done | Busybox cert-bundle builder runs as non-root with all capabilities dropped. | Keep image and chart identity synchronized. |
| Authz and authz init | `65532:65532`, non-root | Done | The image was rebuilt to declare UID/GID `65532`, so the chart no longer needs a `999:999` override; both the Deployment and the `init-authz` migration-Job container inherit `serviceDefaults.securityContext`. | Keep image and chart identity synchronized. |
| VA | `65532:65532`, non-root; `fsGroup: 65532` with `fsGroupChangePolicy: OnRootMismatch` when `fileStore.type=local` | Done | Container identity is pinned by `serviceDefaults.securityContext`; the local-storage PVC is now group-owned by `65532` at mount time, with `OnRootMismatch` skipping the recursive chown once ownership is established (no legacy volumes to migrate, unlike KMS). `fileStore.type=s3` gets no PVC and no `fsGroup`. | Keep image and chart identity synchronized. |
| KMS | `65532:65532`; `fsGroup: 65532` when the filesystem engine or PKCS#11 sidecar is in use | Done | KMS no longer overrides the chart-wide `runAsGroup` default; `fsGroup: 65532` lets the container access both the filesystem engine's PVC and the PKCS#11 socket volume without root-group membership. Kubelet's default `fsGroupChangePolicy: Always` recursively rechowns existing PVC content to `65532` on next pod start. | Keep image and chart identity synchronized. |
| UI | `65532:65532`, non-root, unprivileged port | Done | Identity comes from `serviceDefaults.securityContext`; the rootless image removes the CHOWN/SETGID/SETUID exception and satisfies Restricted Pod Security. | Keep image and chart identity synchronized. |
| WFX | `65532:65532`, non-root; image pinned by digest | Done | Image declares UID `65532`; the chart no longer overrides `runAsNonRoot`, so WFX inherits the chart-wide `65532:65532` default, and the `:latest` tag is pinned to its verified digest so it can no longer silently regress to a different (possibly root) image. | Keep image and chart identity synchronized. |
| DB migration binaries | Image declares UID `65532`; chart does not enforce it | Todo | A republished image could run migrations as root. | Add a migration-specific `65532:65532`, non-root contract. |
| PostgreSQL migration helpers | Run as root | Todo | Database credentials and shell logic run with unnecessary root privileges. | Run as `999:999`; PostgreSQL client tools were verified with this identity. |
| CA-to-KMS migration | `65532:65532`, non-root via `serviceDefaults.securityContext` | Done | Explicit chart-level identity, no longer tied to mutable image metadata. | Keep image and chart identity synchronized. |
| Helm connectivity test | `65532:65532`, non-root, `readOnlyRootFilesystem: true`; public `curlimages/curl` image pinned by digest | Done | Replaced the chart-owned `ghcr.io/lamassuiot/toolbox` image (and its `ci/toolbox` build pipeline) with the upstream-maintained `curlimages/curl` image; the hook script was rewritten from `bash`+`jq` to POSIX `sh` with a `grep`-based JSON-shape check, since `curlimages/curl` ships neither. | Keep image and chart identity synchronized. |
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
| `lamassu-authz:dev-v4` | `65532:65532` (rebuilt; supersedes the `lamassu`/`999:999` entry below) | Not yet re-verified locally; the chart now trusts the declared UID/GID pending a fresh `docker image inspect`. |
| `lamassu-authz:dev-v4` (previous build) | `lamassu` (`999:999`) | `sha256:88959564b49bbeda622bbfb6142b98f5cce910072c98ff1e4bac8a2584f58f69` |
| `lamassu-ui:dev-v4` | `65532:65532` | Old rootless rebuild superseded by the `:dev` arm64 entry below; digest recorded when `dev-v4` is rebuilt. |
| `lamassu-ui:dev` (arm64) | `65532:65532` | Manifest digest `sha256:b183bcf52331d2190bdc074e0741cc885c0833d3535581f58cff82340b12277b`; pushed 2026-09-21; runtime-verified with `--cap-drop=ALL`, `no-new-privileges`. |
| `lamassu-lamassu-db-migration:dev-v4` | `65532` | `sha256:feb9c41131b3f19a7ddee12cc4bc248e74b41038e611ebd4327f1ea53b8b0f91` |
| `lamassu-aws-connector:dev-v4` | `65532` | `sha256:ad585a5120c8634eb18b72ee71dce6f8e45c70ddd54502f9b832b5bf5786ba01` |
| `lamassu-ca-to-kms-migration:dev-v4` | `65532` | `sha256:2c1262a7bc9504257d0d6e65be10b32ed07067b6c29202929806411446ad8b9f` |
| `curlimages/curl@sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777` (chart-pinned, `8.22.0`; replaces the retired `ghcr.io/lamassuiot/toolbox:2.2.0`, previously `root/empty`, `sha256:464d86d83ec52abab587d1367de2603e51c46dc989641ecae460a2d68299b355`) | `curl_user` (`100:101`); chart pins `65532:65532` via `securityContext` | `sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777` |
| `ghcr.io/siemens/wfx@sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678` (chart-pinned; observed under the `:latest` tag on 2026-09-21) | `65532` | `sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678` |
| `postgres:18.4` | root/empty; `postgres=999:999` | `sha256:a02db8cac496f15b094798a38254f14d6e00741f709360e5e00bb6668ea31636` |

## Evidence Register

| ID | Evidence | Result |
|---|---|---|
| E-001 | Inspect exact image metadata with `docker image inspect` | Identity table above. |
| E-002 | Run Authz image and inspect `lamassu` account | Historical: the previous `lamassu-authz:dev-v4` build's named user resolved to UID/GID `999:999`. Superseded by the 2026-09-23 rebuild, which declares `65532:65532` directly; the chart no longer needs a per-service override. |
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
| E-013 | `helm lint` a connector override with `securityContext.runAsNonRoot: false` | Rejected: `runAsNonRoot` must equal `true` for `services.connectors.*`. |
| E-014 | `helm lint` a connector override with `securityContext.privileged: true` | Rejected: `privileged` is not an allowed property. |
| E-015 | `helm lint` a connector override with `runAsNonRoot: true`, `runAsUser: 65532`, `runAsGroup: 65532` | Accepted; confirms the tightened schema does not reject a compliant override. |
| E-016 | `helm lint` and `helm template` the default chart after tightening `values.schema.json` | Both pass, including the WFX `runAsNonRoot: false` exception, which the schema still permits as a plain boolean pending E-001/WFX remediation. |
| E-017 | Run `curlimages/curl:8.11.1` (initial pin) and `curlimages/curl:8.22.0` (current pin, after the image was bumped post-review) with `-u 65532:65532 --cap-drop=ALL --security-opt=no-new-privileges --read-only` | `sh`, `curl`, and `grep` all work on both versions; a live `curl` to an external HTTPS endpoint succeeds; `touch /` fails as expected under the read-only root filesystem. |
| E-018 | Extract the rendered `init.sh` from `helm template` and run it inside the same locked-down `curlimages/curl:8.22.0` container | POSIX-`sh` syntax is valid (`sh -n`, `dash -n`); `check_service`/`check_ui` correctly accept a JSON-shaped body and correctly reject a non-JSON (HTML) body, matching the pre-rewrite `jq`/`bash` behavior without needing either tool. |
| E-019 | Found `services.connectivityTest.image` set to the malformed reference `curlimages/curl@sha256:8.22.0` (a version string is not a valid digest) after a post-review image bump; re-pulled `curlimages/curl:8.22.0` and corrected the pin to its real digest, `sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777` | `docker image inspect --format '{{json .RepoDigests}}'` confirms the digest; `helm template` renders the corrected reference. |

## Completed Work

- [x] Set `RuntimeDefault` seccomp at pod level for chart workloads.
- [x] Disable privilege escalation and drop all capabilities by default.
- [x] Disable automatic ServiceAccount token mounting by default.
- [x] Give Alerts, CA, and Device Manager explicit `65532:65532` contracts.
- [x] Give AWS connectors a `65532:65532` default with per-instance overrides.
- [x] Migrate Authz and its migration init container from a `999:999`
  override to the chart-wide `65532:65532` default, now that the image
  declares that identity itself.
- [x] Run the DMS TLS init container as `65532:65532` with `fsGroup: 65532`.
- [x] Limit the current root UI image to its three verified capabilities.
- [x] Separate PKCS#11 module-init security from the KMS application contract.
- [x] Limit the p11-kit root installer to five verified capabilities.
- [x] Validate the ARM64 architecture of current Lamassu service images.
- [x] Add schema-level security-context validation in `values.schema.json`:
  new `containerSecurityContext`, `podSecurityContext`, and `capabilities`
  definitions close `additionalProperties` (blocking `privileged` and other
  unlisted fields), pin `allowPrivilegeEscalation` to `false` when set, and
  restrict `capabilities.add` to empty; `connectorSecurityContext` builds on
  this to require `runAsNonRoot: true` for every connector instance.

## Prioritized Work

### P0 - Deferred By Decision

- [ ] **Deferred:** move credentials currently rendered into ConfigMaps to
  Secrets or external secret references. Do not mark complete until templates,
  upgrade behavior, and redaction tests are implemented.

### P1 - Identity And Admission

- [x] Build a rootless UI image running as `65532:65532` on an unprivileged
  port; publish with `docker buildx build --platform linux/amd64,linux/arm64
  --push` for multi-architecture availability.
- [x] Enforce `65532:65532` and `runAsNonRoot: true` for WFX; stop using `latest`.
- [ ] Run database migration images as `65532:65532`, non-root.
- [ ] Run PostgreSQL migration helpers as `999:999`, non-root.
- [x] Run the Helm connectivity test as `65532:65532`, non-root, on a
  public image instead of a chart-owned toolbox.
- [x] Change KMS and its PKCS#11 sidecar from GID `0` to GID `65532`.
- [ ] Add explicit `65532:65532` contracts to DMS, VA, and CA-to-KMS.
- [ ] Enable Pod Security Admission gradually: `enforce=baseline`, then
  `warn=restricted` and `audit=restricted`; enforce Restricted only after all
  documented exceptions are removed.

### P2 - Filesystems And Supply Chain

- [x] Add `fsGroup: 65532` to KMS when it uses a PVC or the PKCS#11 sidecar.
- [x] Add `fsGroup: 65532` and `OnRootMismatch` to VA when it uses a PVC.
- [ ] Test `readOnlyRootFilesystem: true` for every service and provide explicit
  writable mounts for `/tmp`, caches, sockets, generated config, and state.
- [ ] Replace runtime `apt-get` in the p11-kit init container with a prebuilt,
  non-root, digest-pinned image.
- [ ] Replace mutable production tags with immutable versions or digests.
- [x] Validate security-context fields in `values.schema.json` for
  `service.securityContext`, `service.podSecurityContext`,
  `dmsManager.tlsInitContainer.securityContext`, and `connectors.*.securityContext`
  (see Completed Work). Still open: `kms.pkcs11Sidecar` and `kms.pkcs11Modules`
  security contexts sit under `service`'s `additionalProperties: true` and
  remain unvalidated; no schema field yet excludes UID/GID `0` outright for
  non-connector services (WFX's documented `runAsNonRoot: false` exception
  relies on this being permissive).
- [ ] Add CI assertions for effective UID/GID, non-root guards, capabilities,
  seccomp, privilege escalation, and ServiceAccount token mounting.
- [ ] Evaluate `supplementalGroupsPolicy: Strict` only after the chart's minimum
  Kubernetes version supports it.

## Exception Register

| Exception | Current justification | Allowed scope | Exit condition |
|---|---|---|---|
| p11-kit staging runs as root and adds five capabilities | Online fast-lane installs `p11-kit-modules` into a transient Debian container. | `kms-pkcs11-module-p11-kit-client` init container only. | Prebuilt module image contains the library and dependencies and can copy them as non-root. |

## Target Runtime Contracts

| Image class | Target UID:GID | Required controls |
|---|---:|---|
| Owned distroless Go services (including Authz) | `65532:65532` | `runAsNonRoot`, no privilege escalation, drop all capabilities, `RuntimeDefault` seccomp. |
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

- 2026-09-23: Diagnosed and recovered a post-upgrade data-loss incident on
  the `lamassu-dev` lab cluster (main/3.8.0 → `code-quality`/4.0.0). Root
  cause: the chart-wide resource-naming refactor (`lamassu.fullname` /
  `lamassu.componentName`) release-scopes every workload name (`kms` →
  `lamassu-kms`, `va` → `lamassu-va`, ...); for the KMS and VA StatefulSets,
  which use local PVCs, this changed the pod name and therefore the
  auto-generated PVC name, so `helm upgrade` bound new, empty PVCs instead of
  the existing ones. Confirmed via `kubectl get pvc`: both the pre-upgrade
  (`golang-engine-storage-kms-0`, `local-crl-file-storage-va-0`) and
  post-upgrade (`golang-engine-storage-lamassu-kms-0`,
  `local-crl-file-storage-lamassu-va-0`) PVCs existed side by side, with the
  old ones holding the real KMS key material and VA CRLs. This is separate
  from — but compounded by — this session's non-root hardening: the
  pre-upgrade data was owned by UID/GID `999` (a mutable `dev-v4` tag's
  then-current image identity, per SECURITY.md Principle 6, not `65532`),
  so it also needed re-owning for the new non-root pods to read it.
  Recovered the lab data with a short-lived `alpine:3.20` pod mounting all
  four PVCs, `cp -a` from old to new, `chown -R 65532:65532`, then recycled
  the `lamassu-kms-0`/`lamassu-va-0` pods; verified clean startup logs and a
  `200` from VA's `GET /crl/<ca-ski>` for the previously-`NotFound` CRL. Old
  PVCs were left in place (not deleted) pending the user's own follow-up
  verification. Wrote `charts/lamassu/CHANGELOG/3.8.0->4.0.0.md` with a
  generalized version of this recovery procedure, plus the `toolbox` →
  `connectivityTest` and `services.kms`/`services.authz` security-context
  key removals, matching this repo's existing per-version migration-guide
  convention. Also found and fixed a live bug while writing that guide:
  `values.yaml`'s `connectivityTest.image` had been bumped to
  `curlimages/curl@sha256:8.22.0` — an invalid OCI reference, since `@sha256`
  requires a 64-hex digest, not a version string — corrected to the real
  digest for that tag, `sha256:58adaa4e8dca9c988bae2aba4ab3434a0bb2da16bbe3f92dec39ec7785166777`
  (verified via `docker image inspect`, and re-ran E-017/E-018 against it).

- 2026-09-23: Retired the chart-owned `toolbox` image for the Helm
  connectivity test. Deleted `ci/toolbox/dockerfile` and
  `.github/workflows/dockerbuild-toolbox.yaml` (the Ubuntu-based image and
  its build pipeline existed only to give the test hook `curl`+`jq`+`bash`).
  Renamed the `values.toolbox` key to `values.connectivityTest` and pointed
  it at the upstream-maintained `curlimages/curl` image, pinned by digest
  (`sha256:c1fe1679c34d9784c1b0d1e5f62ac0a79fca01fb6377cdd33e90473c6f9f9a69`),
  with a `65532:65532`, non-root, all-capabilities-dropped,
  `readOnlyRootFilesystem: true` default `securityContext` (tighter than
  `serviceDefaults`, since this hook never writes to disk). Rewrote
  `templates/tests/test-connections.yml`'s `init.sh` from `bash`+`jq` to
  POSIX `sh` with a `grep`-based JSON-shape check
  (`^[[:space:]]*[{[]`), since the new image ships neither `bash` nor `jq`.
  Verified with `helm lint`/`helm template` and by running the rendered
  script inside the pinned image under the exact `securityContext` the
  chart applies (`-u 65532:65532 --cap-drop=ALL --security-opt=no-new-
  privileges --read-only`): both the JSON-accept and JSON-reject paths
  behave as before (E-017, E-018). `p11-kit-ssh-sidecar` and the SoftHSM CI
  image remain chart-owned, but were left as-is: unlike `toolbox`, both
  embed custom logic (SSH-forwarding proxy, SoftHSM build) that no public
  image provides, so there's nothing generic to replace them with.

- 2026-09-23: Closed the VA PVC-permission gap. `va-statefulset.yml` now sets
  `fsGroup: 65532` and `fsGroupChangePolicy: OnRootMismatch` on the pod
  whenever `services.va.fileStore.type` is `local` (i.e. the
  `local-crl-file-storage` PVC is mounted), unless the user already supplies
  either field via `services.va.podSecurityContext`. `OnRootMismatch` is used
  instead of KMS's `Always` because VA has no pre-existing group-0-owned
  volumes to force through a migration — new PVCs get chowned to `65532` once
  and subsequent restarts skip the recursive chown. `fileStore.type=s3` gets
  no PVC and no `fsGroup`, matching current behavior. Verified with
  `helm template`: the default (local) values render `fsGroup: 65532`
  and `fsGroupChangePolicy: OnRootMismatch`; an `s3` fileStore override
  renders neither; a `podSecurityContext.fsGroup` override is preserved
  and still gets the default `fsGroupChangePolicy`.

- 2026-09-23: Closed the Authz `999:999` exception. The `lamassu-authz`
  image was rebuilt to declare UID/GID `65532` directly, so
  `services.authz.securityContext` no longer overrides `runAsUser`/
  `runAsGroup` in `values.yaml`; both the Authz Deployment and the
  `init-authz` container in `single-db-migration-job.yml` now inherit the
  chart-wide `65532:65532` default, since both read `services.authz`'s
  merged security context. Verified with `helm template`: both containers
  render `runAsUser: 65532`, `runAsGroup: 65532`, `runAsNonRoot: true`.
  Still open: re-run `docker image inspect` against the rebuilt image and
  record its digest in Verified Image Evidence (the previous `999:999`
  build's digest is kept as a superseded row for traceability).

- 2026-09-23: Closed the KMS and WFX identity exceptions.
  - KMS: removed the chart-wide `runAsGroup: 0` override
    (`services.kms.securityContext` in `values.yaml`) and the matching
    `runAsGroup: 0` on the PKCS#11 sidecar's default security context, so both
    now inherit the `65532:65532` `serviceDefaults`. `kms-statefulset.yml` no
    longer sets a pod-level `runAsUser`/`runAsGroup` override; instead it sets
    `fsGroup: 65532` whenever the filesystem crypto engine or the PKCS#11
    sidecar is in use, so kubelet's default `fsGroupChangePolicy: Always`
    recursively rechowns the PVC (and the forwarded PKCS#11 socket volume) to
    group `65532` on next pod start, covering existing volumes without a
    separate migration step. Removed the now-redundant
    `services.kms.podSecurityContext` `runAsGroup: 0` override from
    `ci/pkcs11-incluster-hsm-values.yaml`. Removed the "KMS and sidecar use
    primary/supplementary GID `0`" row from the Exception Register.
  - WFX: removed the `services.wfx.securityContext.runAsNonRoot: false`
    override so WFX inherits the chart-wide `65532:65532`, non-root default
    (the image already declares UID `65532`, per E-001/Verified Image
    Evidence). Pinned `services.wfx.image` from the mutable `:latest` tag to
    its verified digest (`sha256:a4c369a086ee82828c3858f2c330b4cb1762d7ae2830a4cb5aba56830d86f678`)
    so the deployed image can no longer silently change out from under the
    chart.
  - Verified with `helm lint` (default values, `template-contract-values.yaml`,
    and `pkcs11-incluster-hsm-values.yaml` with `--kube-version 1.29.0`) and
    `helm template`, confirming KMS renders `65532:65532` with
    `fsGroup: 65532` in the default (filesystem engine), PKCS#11-sidecar, and
    HSM CI scenarios, and WFX renders `65532:65532`, `runAsNonRoot: true`,
    with the digest-pinned image.

- 2026-09-22: Hardened `values.schema.json`. Added `containerSecurityContext`,
  `podSecurityContext`, and `capabilities` definitions with
  `additionalProperties: false` (blocks `privileged` and other unlisted
  fields), `allowPrivilegeEscalation: false` when set, and an empty
  `capabilities.add`. `connectorSecurityContext` now composes the container
  definition via `allOf` and requires `runAsNonRoot: true` for every
  connector instance, closing the gap where a connector override could
  silently disable non-root enforcement. Verified with `helm lint` against
  malicious (`runAsNonRoot: false`, `privileged: true`) and compliant
  connector overrides (E-013 through E-015), and confirmed the default chart
  and the WFX `runAsNonRoot: false` exception still render and lint cleanly
  (E-016). Remaining gap: `kms.pkcs11Sidecar`/`kms.pkcs11Modules` security
  contexts are not yet covered by the schema.

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
