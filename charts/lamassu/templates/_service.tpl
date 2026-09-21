{{/* Standard single-port ClusterIP Service. Multi-port Services stay explicit. */}}
{{- define "lamassu.service" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- $resourceName := include "lamassu.componentName" (dict "root" .root "component" .name) -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ $resourceName }}
  labels:
    {{- include "lamassu.labels" (dict "root" .root "component" .name) | nindent 4 }}
  {{- with .root.Values.commonAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  selector:
    {{- include "lamassu.selectorLabels" (dict "root" .root "component" .name) | nindent 4 }}
  type: ClusterIP
  ports:
    - name: http
      port: {{ $svc.port }}
      targetPort: {{ $svc.port }}
      protocol: TCP
{{- end -}}
