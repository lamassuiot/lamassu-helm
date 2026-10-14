{{/*
Config file content (the "config" key) of a single AWS connector's ConfigMap.
Takes "root", "connectorID" and "instance". Shared by the ConfigMap and the
Deployment's checksum so that each connector only hashes its own config.
*/}}
{{- define "lamassu.awsConnector.config" -}}
logs:
  level: "info"

{{- include "lamassu.config.eventbus" (dict "root" .root "key" "subscriber_event_bus") | nindent 0 }}

{{- include "lamassu.config.eventbus" (dict "root" .root "key" "subscriber_dlq_event_bus" "dlq" true) | nindent 0 }}

dms_manager_client:
  log_level: debug
  auth_mode: noauth
  protocol: http
  hostname: {{ include "lamassu.componentName" (dict "root" .root "component" "dms-manager") }}
  port: {{ include "lamassu.config.servicePort" (dict "root" .root "svcKey" "dmsManager") }}

device_manager_client:
  log_level: debug
  auth_mode: noauth
  protocol: http
  hostname: {{ include "lamassu.componentName" (dict "root" .root "component" "device-manager") }}
  port: {{ include "lamassu.config.servicePort" (dict "root" .root "svcKey" "deviceManager") }}

ca_client:
  log_level: debug
  auth_mode: noauth
  protocol: http
  hostname: {{ include "lamassu.componentName" (dict "root" .root "component" "ca") }}
  port: {{ include "lamassu.config.servicePort" (dict "root" .root "svcKey" "ca") }}

{{- include "lamassu.config.authzClient" .root | nindent 0 }}

connector_id: {{ .connectorID }}
aws_config:
  {{ .instance.credentials | toYaml | indent 2 | trim }}
{{- include "lamassu.config.otel" .root | nindent 0 }}
{{- end -}}
