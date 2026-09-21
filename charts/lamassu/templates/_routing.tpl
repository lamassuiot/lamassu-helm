{{/*
HTTPRoute through the Lamassu API gateway.

Required keys: root, name, backend, port, path.
Optional keys: rewrite, authLabel, and sections (defaults to ["https"]).
*/}}
{{- define "lamassu.httproute" -}}
{{- $routeName := include "lamassu.componentName" (dict "root" .root "component" .name) -}}
{{- $backendName := include "lamassu.componentName" (dict "root" .root "component" .backend) -}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ $routeName }}
  labels:
    {{- include "lamassu.labels" (dict "root" .root "component" .name) | nindent 4 }}
    {{- with .authLabel }}
    auth: {{ . | quote }}
    {{- end }}
spec:
  parentRefs:
    {{- range (.sections | default (list "https")) }}
    - name: {{ include "lamassu.componentName" (dict "root" $.root "component" "gateway") }}
      sectionName: {{ . }}
    {{- end }}
  rules:
    - matches:
      - path:
          type: PathPrefix
          value: {{ .path }}
      {{- with .rewrite }}
      filters:
      - type: URLRewrite
        urlRewrite:
          path:
            type: ReplacePrefixMatch
            replacePrefixMatch: {{ . | quote }}
      {{- end }}
      backendRefs:
        - name: {{ $backendName }}
          port: {{ .port }}
{{- end -}}
