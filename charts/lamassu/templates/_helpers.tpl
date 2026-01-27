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
