{{- define "lamassu.va.volumeClaimTemplates" -}}
- metadata:
    name: {{ .name }}
  spec:
    accessModes: [ "ReadWriteOnce" ]
    storageClassName: null
    resources:
      requests:
        storage: 1Gi
{{- end -}}
