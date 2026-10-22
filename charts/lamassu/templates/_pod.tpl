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

{{/*
Labels and annotations shared by all Lamassu pod templates.
Optional "configData": already rendered config of the pod's own ConfigMap, for
templates that render several ConfigMaps from one file (takes precedence over "configmap").
Optional "configmap": file name (under templates/) of the ConfigMap mounted by the pod.
Its rendered data is hashed so changes coming from other services' values (e.g. a
dependency's port) also roll the pod; the ConfigMap is mounted via subPath, which
Kubernetes never refreshes in running pods.
*/}}
{{- define "lamassu.podMetadata" -}}
labels:
  {{- $podLabels := mustMergeOverwrite (deepCopy (.svc.labels | default dict)) (deepCopy (.svc.podLabels | default dict)) -}}
  {{- include "lamassu.labels" (dict "root" .root "component" .name "extra" $podLabels) | nindent 2 }}
annotations:
  {{- $rendered := "" }}
  {{- if .configData }}
  {{- $rendered = .configData }}
  {{- else if .configmap }}
  {{- $rendered = include (print .root.Template.BasePath "/" .configmap) .root | splitList "\ndata:\n" | rest | join "" }}
  {{- end }}
  checksum/config: {{ toJson (dict "postgres" .root.Values.postgres "amqp" .root.Values.amqp "auth" .root.Values.auth "observability" .root.Values.observability "service" .svc "configmap" $rendered) | sha256sum }}
  {{- include "lamassu.annotations" (dict "root" .root "extra" .svc.podAnnotations) | nindent 2 }}
{{- end -}}

{{/* Security context that makes an AMQP client TLS Secret readable by the non-root app. */}}
{{- define "lamassu.podSecurityContext" -}}
{{- $securityContext := deepCopy (.svc.podSecurityContext | default dict) -}}
{{- if and .root.Values.amqp.client.secretName (not (hasKey $securityContext "fsGroup")) -}}
{{- $_ := set $securityContext "fsGroup" (dig "runAsGroup" 65532 (.svc.securityContext | default dict)) -}}
{{- end -}}
{{- with $securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Mount configured AMQP CA and optional client certificate Secrets into the app container. */}}
{{- define "lamassu.amqpVolumeMounts" -}}
{{- if .Values.amqp.ca.secretName }}
- name: amqp-ca-certificate
  mountPath: /etc/lamassu/amqp/ca
  readOnly: true
{{- end }}
{{- if .Values.amqp.client.secretName }}
- name: amqp-client-tls
  mountPath: /etc/lamassu/amqp/client
  readOnly: true
{{- end }}
{{- end -}}

{{/* Define Secret volumes shared by all AMQP-consuming workloads. */}}
{{- define "lamassu.amqpVolumes" -}}
{{- with .Values.amqp.ca.secretName }}
- name: amqp-ca-certificate
  secret:
    secretName: {{ . | quote }}
    defaultMode: 0444
    items:
      - key: {{ $.Values.amqp.ca.certificateKey | quote }}
        path: ca.crt
{{- end }}
{{- with .Values.amqp.client.secretName }}
- name: amqp-client-tls
  secret:
    secretName: {{ . | quote }}
    defaultMode: 0440
    items:
      - key: {{ $.Values.amqp.client.certificateKey | quote }}
        path: tls.crt
      - key: {{ $.Values.amqp.client.privateKeyKey | quote }}
        path: tls.key
{{- end }}
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
