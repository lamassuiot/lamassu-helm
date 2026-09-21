{{/*
Resolve the effective configuration for one service.

Callers provide either svcKey (for .Values.services.<key>) or svc (for
already-resolved entries such as connector instances). Service-specific values
override serviceDefaults. The legacy `replicas` key remains supported for
connector and WFX compatibility.
*/}}
{{- define "lamassu.svc.merged" -}}
{{- $overrides := dict -}}
{{- if hasKey . "svc" -}}
{{- $overrides = deepCopy .svc -}}
{{- else -}}
{{- $overrides = deepCopy (index .root.Values.services .svcKey | default dict) -}}
{{- end -}}
{{- if and (hasKey $overrides "replicas") (not (hasKey $overrides "replicaCount")) -}}
{{- $_ := set $overrides "replicaCount" $overrides.replicas -}}
{{- end -}}
{{- $merged := mustMergeOverwrite (deepCopy .root.Values.serviceDefaults) (deepCopy $overrides) -}}
{{- $pullSecrets := list -}}
{{- range $secret := concat (.root.Values.global.imagePullSecrets | default list) ($merged.imagePullSecrets | default list) -}}
{{- if kindIs "string" $secret -}}
{{- $pullSecrets = append $pullSecrets (dict "name" $secret) -}}
{{- else -}}
{{- $pullSecrets = append $pullSecrets $secret -}}
{{- end -}}
{{- end -}}
{{- $_ := set $merged "imagePullSecrets" $pullSecrets -}}
{{- $merged | toYaml -}}
{{- end -}}
