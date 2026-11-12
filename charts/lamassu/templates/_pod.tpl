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
{{- if and (hasKey . "podSecurityContext") (hasKey .podSecurityContext "fsGroup") -}}
{{- $preserveFsGroup = true -}}
{{- end -}}
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
Render credentials into the config file in an init container. Credentials are
never written to a ConfigMap; existingSecret is the preferred source and the
value fields remain only as a backwards-compatible fallback.
*/}}
{{- define "lamassu.configSecretInitItem" -}}
{{- $root := .root | default . -}}
{{- $includePostgres := true -}}
{{- $includeAmqp := true -}}
{{- $includeSmtp := false -}}
{{- if hasKey . "includePostgres" }}{{ $includePostgres = .includePostgres }}{{ end -}}
{{- if hasKey . "includeAmqp" }}{{ $includeAmqp = .includeAmqp }}{{ end -}}
{{- if hasKey . "includeSmtp" }}{{ $includeSmtp = .includeSmtp }}{{ end -}}
- name: render-config
  image: {{ $root.Values.configRender.image | quote }}
  imagePullPolicy: {{ $root.Values.global.imagePullPolicy | quote }}
  securityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true
    runAsGroup: 65532
    runAsNonRoot: true
    runAsUser: 65532
  resources:
    {{- toYaml $root.Values.configRender.resources | nindent 4 }}
  command: ["sh", "-c"]
  args:
    - |
      set -eu
      validate_secret() {
        newline=$(printf '\n_')
        newline=${newline%_}
        carriage_return=$(printf '\r_')
        carriage_return=${carriage_return%_}
        case "$1" in
          *"$newline"*|*"$carriage_return"*|[[:space:]]*|*[[:space:]]|*'__LAMASSU_'*)
            echo "Secret values for rendered configuration must not contain leading or trailing whitespace, newline, carriage return, or Lamassu placeholder characters" >&2
            return 1
            ;;
        esac
      }
      escape() {
        printf '%s' "$1" |
          sed -e 's/\\/\\\\/g' -e "s/'/''/g" -e 's/[&|]/\\&/g'
      }
      {{- if $includePostgres }}
      validate_secret "$LAMASSU_POSTGRES_USERNAME"
      validate_secret "$LAMASSU_POSTGRES_PASSWORD"
      pg_user=$(escape "$LAMASSU_POSTGRES_USERNAME")
      pg_password=$(escape "$LAMASSU_POSTGRES_PASSWORD")
      {{- end }}
      {{- if $includeAmqp }}
      validate_secret "$LAMASSU_AMQP_USERNAME"
      validate_secret "$LAMASSU_AMQP_PASSWORD"
      amqp_user=$(escape "$LAMASSU_AMQP_USERNAME")
      amqp_password=$(escape "$LAMASSU_AMQP_PASSWORD")
      {{- end }}
      {{- if $includeSmtp }}
      validate_secret "$LAMASSU_SMTP_USERNAME"
      validate_secret "$LAMASSU_SMTP_PASSWORD"
      smtp_user=$(escape "$LAMASSU_SMTP_USERNAME")
      smtp_password=$(escape "$LAMASSU_SMTP_PASSWORD")
      {{- end }}
      sed \
        {{- if $includePostgres }}
        -e "s|^\([[:space:]]*username: \)'__LAMASSU_POSTGRES_USERNAME__'\$|\1'$pg_user'|g" \
        -e "s|^\([[:space:]]*password: \)'__LAMASSU_POSTGRES_PASSWORD__'\$|\1'$pg_password'|g" \
        {{- end }}
        {{- if $includeAmqp }}
        -e "s|^\([[:space:]]*username: \)'__LAMASSU_AMQP_USERNAME__'\$|\1'$amqp_user'|g" \
        -e "s|^\([[:space:]]*password: \)'__LAMASSU_AMQP_PASSWORD__'\$|\1'$amqp_password'|g" \
        {{- end }}
        {{- if $includeSmtp }}
        -e "s|^\([[:space:]]*username: \)'__LAMASSU_SMTP_USERNAME__'\$|\1'$smtp_user'|g" \
        -e "s|^\([[:space:]]*password: \)'__LAMASSU_SMTP_PASSWORD__'\$|\1'$smtp_password'|g" \
        {{- end }}
        /config-template/config > /config/config
      if grep -Eq "^[[:space:]]*(username|password): '__LAMASSU_(POSTGRES_USERNAME|POSTGRES_PASSWORD|AMQP_USERNAME|AMQP_PASSWORD|SMTP_USERNAME|SMTP_PASSWORD)__'\$" /config/config; then
        echo "Unresolved Lamassu credential placeholder remains after Secret rendering" >&2
        exit 1
      fi
  env:
    {{- if $includePostgres }}
    - name: LAMASSU_POSTGRES_USERNAME
      {{- if $root.Values.postgres.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.postgres.existingSecret | quote }}
          key: {{ $root.Values.postgres.usernameKey | quote }}
      {{- else }}
      value: {{ $root.Values.postgres.username | quote }}
      {{- end }}
    - name: LAMASSU_POSTGRES_PASSWORD
      {{- if $root.Values.postgres.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.postgres.existingSecret | quote }}
          key: {{ $root.Values.postgres.passwordKey | quote }}
      {{- else }}
      value: {{ $root.Values.postgres.password | quote }}
      {{- end }}
    {{- end }}
    {{- if $includeAmqp }}
    - name: LAMASSU_AMQP_USERNAME
      {{- if $root.Values.amqp.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.amqp.existingSecret | quote }}
          key: {{ $root.Values.amqp.usernameKey | quote }}
      {{- else }}
      value: {{ $root.Values.amqp.username | quote }}
      {{- end }}
    - name: LAMASSU_AMQP_PASSWORD
      {{- if $root.Values.amqp.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.amqp.existingSecret | quote }}
          key: {{ $root.Values.amqp.passwordKey | quote }}
      {{- else }}
      value: {{ $root.Values.amqp.password | quote }}
      {{- end }}
    {{- end }}
    {{- if $includeSmtp }}
    - name: LAMASSU_SMTP_USERNAME
      {{- if $root.Values.services.alerts.smtp_server.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.services.alerts.smtp_server.existingSecret | quote }}
          key: {{ $root.Values.services.alerts.smtp_server.usernameKey | quote }}
      {{- else }}
      value: {{ $root.Values.services.alerts.smtp_server.username | quote }}
      {{- end }}
    - name: LAMASSU_SMTP_PASSWORD
      {{- if $root.Values.services.alerts.smtp_server.existingSecret }}
      valueFrom:
        secretKeyRef:
          name: {{ $root.Values.services.alerts.smtp_server.existingSecret | quote }}
          key: {{ $root.Values.services.alerts.smtp_server.passwordKey | quote }}
      {{- else }}
      value: {{ $root.Values.services.alerts.smtp_server.password | quote }}
      {{- end }}
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
