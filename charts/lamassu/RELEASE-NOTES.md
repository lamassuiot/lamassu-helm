
## Unreleased

### Breaking changes

- Chart-owned Kubernetes resources now use release-scoped names in the form
  `<release>-lamassu-<component>`. Existing StatefulSet PVCs keep their old
  names, so upgrades must explicitly migrate or rebind persistent data.
- `services.connectors` is now a map keyed by connector ID. Move each former
  list item's `id` to the map key.
- The chart no longer injects pod anti-affinity or topology spread rules.
  Configure `affinity` and `topologySpreadConstraints` explicitly when needed.

### Improvements

- Adds standard Helm labels, secure pod defaults, optional ServiceAccount
  creation, independent startup/readiness/liveness probes, and config checksum
  rollouts.
- Uses Gateway API `v1`, validates values with JSON Schema, and validates
  rendered built-in resources with kubeconform in CI.
- Generates `VALUES.md` from `values.yaml` with helm-docs.

<a name="lamassu-3.8.0"></a>
## [lamassu-3.8.0](https://github.com/lamassuiot/lamassu-helm/compare/lamassu-3.7.0...lamassu-3.8.0) (2026-06-11)
