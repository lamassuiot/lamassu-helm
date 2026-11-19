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

{{/* Shared pod security context with an optional override for workload-specific settings. */}}
{{- define "lamassu.podSecurityContext" -}}
{{- $securityContext := deepCopy (.svc.podSecurityContext | default dict) -}}
{{- if hasKey . "podSecurityContext" -}}
{{- $securityContext = deepCopy .podSecurityContext -}}
{{- end -}}
{{- if .root.Values.amqp.client.secretName -}}
{{- $preserveFsGroup := and (hasKey $securityContext "fsGroup") (ne (int $securityContext.fsGroup) 65532) -}}
{{- if not $preserveFsGroup -}}
{{- $_ := set $securityContext "fsGroup" (dig "runAsGroup" 65532 (.svc.securityContext | default dict)) -}}
{{- end -}}
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

{{/*
Expose the credential environment variables expected by lamassuiot's config
loader. The application receives Secret-backed values directly; the ConfigMap
contains only non-secret configuration.
*/}}
{{- define "lamassu.configCredentialEnv" -}}
{{- $root := .root | default . -}}
{{- $includePostgres := true -}}
{{- $includeAmqp := true -}}
{{- $includeSmtp := false -}}
{{- if hasKey . "includePostgres" }}{{ $includePostgres = .includePostgres }}{{ end -}}
{{- if hasKey . "includeAmqp" }}{{ $includeAmqp = .includeAmqp }}{{ end -}}
{{- if hasKey . "includeSmtp" }}{{ $includeSmtp = .includeSmtp }}{{ end -}}
{{- if $includePostgres }}
- name: LAMASSU_POSTGRES_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.postgres.existingSecret | quote }}
      key: {{ $root.Values.postgres.usernameKey | quote }}
- name: LAMASSU_POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.postgres.existingSecret | quote }}
      key: {{ $root.Values.postgres.passwordKey | quote }}
{{- end }}
{{- if $includeAmqp }}
- name: LAMASSU_AMQP_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.amqp.existingSecret | quote }}
      key: {{ $root.Values.amqp.usernameKey | quote }}
- name: LAMASSU_AMQP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.amqp.existingSecret | quote }}
      key: {{ $root.Values.amqp.passwordKey | quote }}
{{- end }}
{{- if $includeSmtp }}
- name: LAMASSU_SMTP_USERNAME
  {{- if $root.Values.services.alerts.smtp_server.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.services.alerts.smtp_server.existingSecret | quote }}
      key: {{ $root.Values.services.alerts.smtp_server.usernameKey | quote }}
  {{- else }}
  value: ""
  {{- end }}
- name: LAMASSU_SMTP_PASSWORD
  {{- if $root.Values.services.alerts.smtp_server.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.services.alerts.smtp_server.existingSecret | quote }}
      key: {{ $root.Values.services.alerts.smtp_server.passwordKey | quote }}
  {{- else }}
  value: ""
  {{- end }}
{{- end }}
{{- end -}}

{{- define "lamassu.authzDatabaseCredentialEnv" -}}
{{- $root := .root | default . -}}
- name: LAMASSU_AUTHZ_DB_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.postgres.existingSecret | quote }}
      key: {{ $root.Values.postgres.usernameKey | quote }}
- name: LAMASSU_AUTHZ_DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.postgres.existingSecret | quote }}
      key: {{ $root.Values.postgres.passwordKey | quote }}
{{- end -}}

{{- define "lamassu.authzCredentialEnv" -}}
{{- $root := .root | default . -}}
{{- $names := dict -}}
{{- range $schema, $_ := $root.Values.services.authz.credentials }}
{{- $envPart := upper (regexReplaceAll "[^[:alnum:]]" $schema "_") -}}
{{- if hasKey $names $envPart }}
{{- fail (printf "authz credential schemas %q and %q produce the same environment variable name" (get $names $envPart) $schema) -}}
{{- end }}
{{- $_ := set $names $envPart $schema -}}
{{- range $field := list "username" "password" }}
- name: LAMASSU_AUTHZ_CREDENTIALS_{{ $envPart }}_{{ upper $field }}
  valueFrom:
    secretKeyRef:
      name: {{ $root.Values.postgres.existingSecret | quote }}
      key: {{ if eq $field "username" }}{{ $root.Values.postgres.usernameKey | quote }}{{ else }}{{ $root.Values.postgres.passwordKey | quote }}{{ end }}
{{- end }}
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
