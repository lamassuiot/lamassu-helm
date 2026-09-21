{{/* HorizontalPodAutoscaler for a Deployment or StatefulSet. */}}
{{- define "lamassu.hpa" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- $resourceName := include "lamassu.componentName" (dict "root" .root "component" .name) -}}
{{- if $svc.autoscaling.enabled }}
{{- if gt (int $svc.autoscaling.minReplicas) (int $svc.autoscaling.maxReplicas) -}}
{{- fail (printf "services.%s.autoscaling.minReplicas cannot exceed maxReplicas" .name) -}}
{{- end -}}
{{- if and (not $svc.autoscaling.targetCPUUtilizationPercentage) (not $svc.autoscaling.targetMemoryUtilizationPercentage) -}}
{{- fail (printf "services.%s.autoscaling requires a CPU or memory utilization target" .name) -}}
{{- end -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $resourceName }}
  labels:
    {{- include "lamassu.labels" (dict "root" .root "component" .name) | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ .kind | default "Deployment" }}
    name: {{ $resourceName }}
  minReplicas: {{ $svc.autoscaling.minReplicas }}
  maxReplicas: {{ $svc.autoscaling.maxReplicas }}
  metrics:
    {{- if $svc.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $svc.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if $svc.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ $svc.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
{{- end -}}

{{/* PDB only renders when the effective replica count can exceed one. */}}
{{- define "lamassu.pdb" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- $resourceName := include "lamassu.componentName" (dict "root" .root "component" .name) -}}
{{- if gt (int (ternary $svc.autoscaling.minReplicas $svc.replicaCount $svc.autoscaling.enabled)) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $resourceName }}
  labels:
    {{- include "lamassu.labels" (dict "root" .root "component" .name) | nindent 4 }}
spec:
  minAvailable: {{ $svc.pdb.minAvailable }}
  selector:
    matchLabels:
      {{- include "lamassu.selectorLabels" (dict "root" .root "component" .name) | nindent 6 }}
{{- end }}
{{- end -}}
