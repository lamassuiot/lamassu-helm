{{/*
Fails the render if autoscaling bounds are inconsistent: min > max, or neither
a CPU nor a memory target is set. Call before rendering a HorizontalPodAutoscaler.

dict: name (service key, for the error message), autoscaling (svc.autoscaling)
*/}}
{{- define "lamassu.autoscaling.validate" -}}
{{- if gt (int .autoscaling.minReplicas) (int .autoscaling.maxReplicas) -}}
{{- fail (printf "services.%s.autoscaling.minReplicas cannot exceed maxReplicas" .name) -}}
{{- end -}}
{{- if and (not .autoscaling.targetCPUUtilizationPercentage) (not .autoscaling.targetMemoryUtilizationPercentage) -}}
{{- fail (printf "services.%s.autoscaling requires a CPU or memory utilization target" .name) -}}
{{- end -}}
{{- end -}}

{{/*
Metrics list for a HorizontalPodAutoscaler's spec.metrics.

Argument: svc.autoscaling (must have already passed lamassu.autoscaling.validate)
*/}}
{{- define "lamassu.autoscaling.metrics" -}}
{{- if .targetCPUUtilizationPercentage }}
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: {{ .targetCPUUtilizationPercentage }}
{{- end }}
{{- if .targetMemoryUtilizationPercentage }}
- type: Resource
  resource:
    name: memory
    target:
      type: Utilization
      averageUtilization: {{ .targetMemoryUtilizationPercentage }}
{{- end }}
{{- end -}}

{{/*
"true" when a PodDisruptionBudget should render for this service, i.e. its
effective replica count (fixed, or the autoscaling floor) can exceed one.

Argument: merged svc (from lamassu.svc.merged)
*/}}
{{- define "lamassu.pdb.enabled" -}}
{{- gt (int (ternary .autoscaling.minReplicas .replicaCount .autoscaling.enabled)) 1 -}}
{{- end -}}
