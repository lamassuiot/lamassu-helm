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

{{/*
Render credentials into the config file in an init container. Credentials are
never written to a ConfigMap; existingSecret is the preferred source and the
value fields remain only as a backwards-compatible fallback.
*/}}
{{- define "lamassu.configSecretInitItem" -}}
- name: render-config
  image: docker.io/library/busybox:1.36
  imagePullPolicy: IfNotPresent
  command: ["sh", "-c"]
  args:
    - |
      set -eu
      escape() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
      pg_user=$(escape "$LAMASSU_POSTGRES_USERNAME")
      pg_password=$(escape "$LAMASSU_POSTGRES_PASSWORD")
      amqp_user=$(escape "$LAMASSU_AMQP_USERNAME")
      amqp_password=$(escape "$LAMASSU_AMQP_PASSWORD")
      smtp_user=$(escape "$LAMASSU_SMTP_USERNAME")
      smtp_password=$(escape "$LAMASSU_SMTP_PASSWORD")
      sed \
        -e "s|__LAMASSU_POSTGRES_USERNAME__|$pg_user|g" \
        -e "s|__LAMASSU_POSTGRES_PASSWORD__|$pg_password|g" \
        -e "s|__LAMASSU_AMQP_USERNAME__|$amqp_user|g" \
        -e "s|__LAMASSU_AMQP_PASSWORD__|$amqp_password|g" \
        -e "s|__LAMASSU_SMTP_USERNAME__|$smtp_user|g" \
        -e "s|__LAMASSU_SMTP_PASSWORD__|$smtp_password|g" \
        /config-template/config > /config/config
  env:
    - name: LAMASSU_POSTGRES_USERNAME
      {{- if .Values.postgres.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.postgres.existingSecret | quote }}
          key: {{ .Values.postgres.usernameKey | quote }}
      {{- else }}
      value: {{ .Values.postgres.username | quote }}
      {{- end }}
    - name: LAMASSU_POSTGRES_PASSWORD
      {{- if .Values.postgres.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.postgres.existingSecret | quote }}
          key: {{ .Values.postgres.passwordKey | quote }}
      {{- else }}
      value: {{ .Values.postgres.password | quote }}
      {{- end }}
    - name: LAMASSU_AMQP_USERNAME
      {{- if .Values.amqp.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.amqp.existingSecret | quote }}
          key: {{ .Values.amqp.usernameKey | quote }}
      {{- else }}
      value: {{ .Values.amqp.username | quote }}
      {{- end }}
    - name: LAMASSU_AMQP_PASSWORD
      {{- if .Values.amqp.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.amqp.existingSecret | quote }}
          key: {{ .Values.amqp.passwordKey | quote }}
      {{- else }}
      value: {{ .Values.amqp.password | quote }}
      {{- end }}
    - name: LAMASSU_SMTP_USERNAME
      {{- if .Values.services.alerts.smtp_server.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.services.alerts.smtp_server.existingSecret | quote }}
          key: {{ .Values.services.alerts.smtp_server.usernameKey | quote }}
      {{- else }}
      value: {{ .Values.services.alerts.smtp_server.username | quote }}
      {{- end }}
    - name: LAMASSU_SMTP_PASSWORD
      {{- if .Values.services.alerts.smtp_server.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ .Values.services.alerts.smtp_server.existingSecret | quote }}
          key: {{ .Values.services.alerts.smtp_server.passwordKey | quote }}
      {{- else }}
      value: {{ .Values.services.alerts.smtp_server.password | quote }}
      {{- end }}
  volumeMounts:
    - name: config-template
      mountPath: /config-template
      readOnly: true
    - name: rendered-config
      mountPath: /config
{{- end -}}

{{- define "lamassu.configSecretInit" -}}
initContainers:
  {{- include "lamassu.configSecretInitItem" . | nindent 2 }}
{{- end -}}

{{- define "lamassu.configSecretVolumes" -}}
- name: config-template
  configMap:
    name: {{ .configName }}
- name: rendered-config
  emptyDir:
    medium: Memory
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
