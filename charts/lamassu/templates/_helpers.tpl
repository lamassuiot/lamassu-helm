{{/* Chart name used by labels and generated resource names. */}}
{{- define "lamassu.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Release-scoped base name. */}}
{{- define "lamassu.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Release-scoped name for one Lamassu component or supporting resource. */}}
{{- define "lamassu.componentName" -}}
{{- $base := include "lamassu.fullname" .root -}}
{{- if .component -}}
{{- printf "%s-%s" $base .component | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $base -}}
{{- end -}}
{{- end -}}

{{/* Chart label value. */}}
{{- define "lamassu.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Immutable labels used by workload selectors and Services. */}}
{{- define "lamassu.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lamassu.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app: {{ .component }}
{{- end -}}

{{/* Standard Helm labels plus chart-wide and resource-specific additions. */}}
{{- define "lamassu.labels" -}}
{{- $custom := mustMergeOverwrite (deepCopy (.root.Values.commonLabels | default dict)) (deepCopy (.extra | default dict)) -}}
{{- $standard := dict
  "helm.sh/chart" (include "lamassu.chart" .root)
  "app.kubernetes.io/managed-by" .root.Release.Service
  "app.kubernetes.io/part-of" (include "lamassu.name" .root)
  "app.kubernetes.io/name" (include "lamassu.name" .root)
  "app.kubernetes.io/instance" .root.Release.Name -}}
{{- if .component -}}
{{- $_ := set $standard "app.kubernetes.io/component" .component -}}
{{- $_ := set $standard "app" .component -}}
{{- end -}}
{{- if .root.Chart.AppVersion -}}
{{- $_ := set $standard "app.kubernetes.io/version" .root.Chart.AppVersion -}}
{{- end -}}
{{- mustMergeOverwrite $custom $standard | toYaml -}}
{{- end -}}

{{/* Chart-wide annotations plus resource-specific additions. */}}
{{- define "lamassu.annotations" -}}
{{- $annotations := mustMergeOverwrite
  (deepCopy (.root.Values.commonAnnotations | default dict))
  (deepCopy (.extra | default dict)) -}}
{{- if $annotations -}}
{{- $annotations | toYaml -}}
{{- end -}}
{{- end -}}

{{/* Labels and annotations for a non-workload resource. */}}
{{- define "lamassu.resourceMetadata" -}}
labels:
  {{- include "lamassu.labels" . | nindent 2 }}
{{- $annotations := include "lamassu.annotations" (dict "root" .root "extra" (.extraAnnotations | default dict)) -}}
{{- if $annotations }}
annotations:
  {{- $annotations | nindent 2 }}
{{- end }}
{{- end -}}

{{/* ServiceAccount used by every Lamassu pod. */}}
{{- define "lamassu.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "lamassu.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Issuer for the downstream certificate. The unscoped name was emitted by older
fast-lane values and referred to the chart-managed Issuer.
*/}}
{{- define "downstream.issuerName" -}}
{{- $issuer := .Values.tls.certManagerOptions.issuer | default "" -}}
{{- if or (empty $issuer) (eq $issuer "downstream-ca-selfsigned-issuer") -}}
{{- include "lamassu.componentName" (dict "root" . "component" "downstream-ca-selfsigned-issuer") -}}
{{- else -}}
{{- $issuer -}}
{{- end -}}
{{- end -}}

{{/* Downstream certificate Secret, generated or supplied by the operator. */}}
{{- define "downstream.certSecret" -}}
{{- if eq .Values.tls.type "external" -}}
{{- .Values.tls.externalOptions.secretName -}}
{{- else -}}
{{- include "lamassu.componentName" (dict "root" . "component" "downstream-tls") -}}
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
