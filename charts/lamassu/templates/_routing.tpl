{{/*
parentRefs entry pointing HTTPRoutes at the shared Envoy Gateway. Every
Lamassu route attaches to the same gateway, so this is the one fragment
worth sharing; the rest of an HTTPRoute (matches/filters/backendRefs) is
route-specific and stays explicit in each route's own file.

dict: root, sections (optional, list of gateway listener names, default ["https"])
*/}}
{{- define "lamassu.gatewayParentRef" -}}
{{- range (.sections | default (list "https")) }}
- name: {{ include "lamassu.componentName" (dict "root" $.root "component" "gateway") }}
  sectionName: {{ . }}
{{- end }}
{{- end -}}
