{{- define "downstream.certSecret" -}}
  {{- if .Values.tls.selfSigned -}}
    {{- print "downstream-cert" -}}
  {{- else -}}
    {{- print .Values.tls.secretName -}}
  {{- end -}}
{{- end -}}

{{/*
Check if KMS has a filesystem crypto engine configured
*/}}
{{- define "kms.hasFilesystemEngine" -}}
  {{- $hasFilesystem := false -}}
  {{- range .Values.services.kms.cryptoEngines.engines -}}
    {{- if eq .type "filesystem" -}}
      {{- $hasFilesystem = true -}}
    {{- end -}}
  {{- end -}}
  {{- $hasFilesystem -}}
{{- end -}}

{{- define "app.migrations" -}}
jobs:
  - name: migration-v3.6.2
    targetVersion: "3.6.2"
    dbs:
      - db: kms
        migration_id: "20251031174938"
      - db: ca
        migration_id: "20251106120000"
{{- end -}}
