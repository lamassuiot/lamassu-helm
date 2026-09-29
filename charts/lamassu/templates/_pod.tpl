{{/* Stable metadata shared by all Lamassu workloads. */}}
{{- define "lamassu.workloadMetadata" -}}
labels:
  {{- include "lamassu.labels" (dict "root" .root "component" .name "extra" .svc.labels) | nindent 2 }}
{{- $annotations := include "lamassu.annotations" (dict "root" .root "extra" .svc.annotations) -}}
{{- if $annotations }}
annotations:
  {{- $annotations | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Labels and annotations shared by all Lamassu pod templates. */}}
{{- define "lamassu.podMetadata" -}}
labels:
  {{- $podLabels := mustMergeOverwrite (deepCopy (.svc.labels | default dict)) (deepCopy (.svc.podLabels | default dict)) -}}
  {{- include "lamassu.labels" (dict "root" .root "component" .name "extra" $podLabels) | nindent 2 }}
annotations:
  checksum/config: {{ toJson (dict "postgres" .root.Values.postgres "amqp" .root.Values.amqp "auth" .root.Values.auth "observability" .root.Values.observability "service" .svc) | sha256sum }}
  {{- include "lamassu.annotations" (dict "root" .root "extra" .svc.podAnnotations) | nindent 2 }}
{{- end -}}

{{/* User-supplied pod placement policy. */}}
{{- define "lamassu.podPlacement" -}}
{{- with .svc.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .svc.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .svc.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .svc.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Named HTTP probe with the standard Kubernetes timing controls. */}}
{{- define "lamassu.httpProbe" -}}
{{- if .probe.enabled }}
{{ .name }}:
  httpGet:
    path: {{ .probe.path }}
    port: {{ .port }}
  initialDelaySeconds: {{ .probe.initialDelaySeconds }}
  periodSeconds: {{ .probe.periodSeconds }}
  timeoutSeconds: {{ .probe.timeoutSeconds }}
  successThreshold: {{ .probe.successThreshold }}
  failureThreshold: {{ .probe.failureThreshold }}
{{- end }}
{{- end -}}

{{/* Named TCP probe for multi-port services such as WFX. */}}
{{- define "lamassu.tcpProbe" -}}
{{- if .probe.enabled }}
{{ .name }}:
  tcpSocket:
    port: {{ .port }}
  initialDelaySeconds: {{ .probe.initialDelaySeconds }}
  periodSeconds: {{ .probe.periodSeconds }}
  timeoutSeconds: {{ .probe.timeoutSeconds }}
  successThreshold: {{ .probe.successThreshold }}
  failureThreshold: {{ .probe.failureThreshold }}
{{- end }}
{{- end -}}
