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

connector_id: {{ .connectorID }}
aws_config:
  {{- $credentials := deepCopy (.instance.credentials | default dict) -}}
  {{- if (dig "credentialsSecret" "name" "" .instance) -}}
    {{- $_ := unset $credentials "access_key_id" -}}
    {{- $_ := unset $credentials "secret_access_key" -}}
    {{- $_ := set $credentials "access_key_id_env" (include "lamassu.awsCredentialEnvName" (dict "scope" "CONNECTOR" "id" $.connectorID "credential" "ACCESS_KEY_ID")) -}}
    {{- $_ := set $credentials "secret_access_key_env" (include "lamassu.awsCredentialEnvName" (dict "scope" "CONNECTOR" "id" $.connectorID "credential" "SECRET_ACCESS_KEY")) -}}
  {{- end }}
  {{ $credentials | toYaml | nindent 2 }}
{{- end }}
