{{/*
Shared partials for the per-service app config rendered into each ConfigMap's
`data.config` block. These are genuinely repeated blocks (HTTP server, DB
storage, AMQP event bus, OTel), not selector/scheduling boilerplate — kept
separate from _lib.tpl on purpose.
*/}}

{{/*
Common server/openapi header. Context dict:
  logsLevel    top-level `logs.level` value
  healthCheck  server.health_check value; key is omitted entirely if unset
  sse          set true to emit `sse_enabled: true` (device-manager only)
*/}}
{{- define "lamassu.config.header" -}}
logs:
  level: "{{ .logsLevel }}"

server:
  log_level: "debug"
  {{- if hasKey . "healthCheck" }}
  health_check: {{ .healthCheck }}
  {{- end }}
  listen_address: "0.0.0.0"
  port: 8085
  protocol: "http" #http | https
{{- if .sse }}

sse_enabled: true
{{- end }}

openapi:
  enabled: true
{{- end -}}

{{/*
AMQP event bus block. Context dict:
  root   chart root context ($)
  key    section name, e.g. "publisher_event_bus" | "subscriber_event_bus" | "subscriber_dlq_event_bus"
  dlq    set true to add `exchange: lamassu-dlq`
*/}}
{{- define "lamassu.config.eventbus" -}}
{{ .key }}:
  log_level: "debug"
  enabled: true
  provider: amqp
  protocol: amqp #amqp | amqps
  hostname: {{ .root.Values.amqp.hostname }}
  port: {{ .root.Values.amqp.port }}
  {{- if .dlq }}
  exchange: lamassu-dlq
  {{- end }}
  basic_auth:
    enabled: true
    username: "{{ .root.Values.amqp.username }}"
    password: "{{ .root.Values.amqp.password }}"
{{- end -}}

{{/*
PostgreSQL storage block. Context: chart root ($), or a dict:
  root      chart root context ($)
  key       top-level section name (default: "storage")
  database  optional `database` field to append (e.g. authz's per-schema DBs)
*/}}
{{- define "lamassu.config.storage" -}}
{{- $root := . -}}
{{- $key := "storage" -}}
{{- $database := "" -}}
{{- if hasKey . "root" -}}
{{- $root = .root -}}
{{- $key = .key | default "storage" -}}
{{- $database = .database -}}
{{- end -}}
{{ $key }}:
  log_level: "info"
  provider: "postgres" #couch_db | postgres | dynamo_db
  hostname: {{ $root.Values.postgres.hostname }}
  port: {{ $root.Values.postgres.port }}
  username: "{{ $root.Values.postgres.username }}"
  password: "{{ $root.Values.postgres.password }}"
  {{- with $database }}
  database: {{ . }}
  {{- end }}
{{- end -}}

{{/*
Client block for calling another Lamassu service's HTTP API. Context dict:
  key       section name, e.g. "kms_client" | "authz_client" | "ca_client" | "device_manager_client" | "dms_manager_client"
  hostname  target Kubernetes Service name
  port      target port (default: 8085, the chart-wide service port)
*/}}
{{- define "lamassu.config.client" -}}
{{ .key }}:
  log_level: debug
  auth_mode: noauth
  protocol: http
  hostname: {{ .hostname }}
  port: {{ .port | default 8085 }}
{{- end -}}

{{/* OTel traces/logging block, guarded by observability.enabled. Context: chart root ($) */}}
{{- define "lamassu.config.otel" -}}
{{- if .Values.observability.enabled }}
otel:
  traces:
    enabled: true
    hostname: {{ .Values.observability.traces.hostname }}
    port: {{ .Values.observability.traces.port }}
    scheme: {{ .Values.observability.traces.scheme }}
    base_path: "{{ .Values.observability.traces.basePath }}"
  logging:
    enabled: true
    hostname: {{ .Values.observability.logs.hostname }}
    port: {{ .Values.observability.logs.port }}
    scheme: {{ .Values.observability.logs.scheme }}
    base_path: "{{ .Values.observability.logs.basePath }}"
  metrics:
    enabled: false
{{- end }}
{{- end -}}
