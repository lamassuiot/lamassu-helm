{{/*
Shared library for Lamassu service resources.

Every Lamassu service (ca, kms, va, ui, alerts, device-manager, dms-manager,
aws-connector instances) is rendered from the generic templates below. Generic
configuration lives in .Values.serviceDefaults and can be overridden per
service under .Values.services.<name> — the two are deep-merged with the
per-service block taking precedence.

All templates take a dict context with:
  root          (required) the chart root context ($)
  name          (required) resource name, also used as the `app` selector label
  svcKey        key under .Values.services to merge over serviceDefaults
  svc           pre-resolved override dict (used instead of svcKey, e.g. for
                connector instances that live in a list)

"lamassu.workload" additionally accepts:
  kind                  Deployment (default) | StatefulSet
  serviceName           StatefulSet headless service name
  tty                   set to false to drop `tty: true` from the container
  configMapName         config ConfigMap mounted at /etc/lamassuiot/config.yml.
                        Defaults to "<name>-config"; set "" to skip the mount.
  env                   pre-rendered YAML string of extra env list items
  initContainers        pre-rendered YAML string of initContainer list items
  volumeMounts          pre-rendered YAML string of extra volumeMount list items
  volumes               pre-rendered YAML string of extra volume list items
  volumeClaimTemplates  pre-rendered YAML string of volumeClaimTemplate items

"lamassu.hpa" additionally accepts:
  kind          scaleTargetRef kind: Deployment (default) | StatefulSet
*/}}

{{- define "lamassu.svc.merged" -}}
{{- $overrides := dict -}}
{{- if hasKey . "svc" -}}
{{- $overrides = .svc -}}
{{- else -}}
{{- $overrides = index .root.Values.services .svcKey | default dict -}}
{{- end -}}
{{- mustMergeOverwrite (deepCopy .root.Values.serviceDefaults) (deepCopy $overrides) | toYaml -}}
{{- end -}}

{{- define "lamassu.workload" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- $root := .root -}}
{{- $name := .name -}}
{{- $configMapName := hasKey . "configMapName" | ternary .configMapName (printf "%s-config" $name) -}}
{{- $tty := hasKey . "tty" | ternary .tty true -}}
apiVersion: apps/v1
kind: {{ .kind | default "Deployment" }}
metadata:
  name: {{ $name }}
  namespace: {{ $root.Release.Namespace }}
  annotations:
    reloader.stakater.com/auto: "true"
    {{- with $svc.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    app: {{ $name }}
    {{- with $svc.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- if not $svc.autoscaling.enabled }}
  replicas: {{ $svc.replicaCount }}
  {{- end }}
  {{- with .serviceName }}
  serviceName: {{ . | quote }}
  {{- end }}
  selector:
    matchLabels:
      app: {{ $name }}
  template:
    metadata:
      labels:
        app: {{ $name }}
        {{- with $svc.labels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- with $svc.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with $svc.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with $svc.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $svc.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .initContainers }}
      initContainers:
        {{- . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ $name }}
          image: {{ $svc.image }}
          imagePullPolicy: {{ $root.Values.global.imagePullPolicy | quote }}
          {{- if $tty }}
          tty: true
          {{- end }}
          {{- with $svc.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if or .env $svc.extraEnv }}
          env:
            {{- with .env }}
            {{- . | nindent 12 }}
            {{- end }}
            {{- with $svc.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
          livenessProbe:
            httpGet:
              path: {{ $svc.probes.path }}
              port: {{ $svc.port }}
            initialDelaySeconds: {{ $svc.probes.initialDelaySeconds }}
            periodSeconds: {{ $svc.probes.periodSeconds }}
          readinessProbe:
            httpGet:
              path: {{ $svc.probes.path }}
              port: {{ $svc.port }}
            initialDelaySeconds: {{ $svc.probes.initialDelaySeconds }}
            periodSeconds: {{ $svc.probes.periodSeconds }}
          {{- with $svc.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if or $configMapName .volumeMounts }}
          volumeMounts:
            {{- if $configMapName }}
            - name: api-config
              mountPath: /etc/lamassuiot/config.yml
              subPath: config
            {{- end }}
            {{- with .volumeMounts }}
            {{- . | nindent 12 }}
            {{- end }}
          {{- end }}
          ports:
            - containerPort: {{ $svc.port }}
      {{- with .sidecars }}
      {{- . | nindent 8 }}
      {{- end }}
      restartPolicy: Always
      {{- with $svc.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $svc.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if $svc.affinity }}
      affinity:
        {{- toYaml $svc.affinity | nindent 8 }}
      {{- else }}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: {{ $name }}
                topologyKey: kubernetes.io/hostname
      {{- end }}
      {{- if $svc.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml $svc.topologySpreadConstraints | nindent 8 }}
      {{- else }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: {{ $name }}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: {{ $name }}
      {{- end }}
      {{- if or $configMapName .volumes }}
      volumes:
        {{- if $configMapName }}
        - name: api-config
          configMap:
            name: {{ $configMapName }}
        {{- end }}
        {{- with .volumes }}
        {{- . | nindent 8 }}
        {{- end }}
      {{- end }}
  {{- with .volumeClaimTemplates }}
  volumeClaimTemplates:
    {{- . | nindent 2 }}
  {{- end }}
{{- end -}}

{{- define "lamassu.service" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
spec:
  selector:
    app: {{ .name }}
  type: ClusterIP
  ports:
  - name: http
    port: {{ $svc.port }}
    targetPort: {{ $svc.port }}
    protocol: TCP
{{- end -}}

{{- define "lamassu.hpa" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- if $svc.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ .kind | default "Deployment" }}
    name: {{ .name }}
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

{{/* PDB only renders when the effective replica count can exceed 1 */}}
{{- define "lamassu.pdb" -}}
{{- $svc := include "lamassu.svc.merged" . | fromYaml -}}
{{- if gt (int (ternary $svc.autoscaling.minReplicas $svc.replicaCount $svc.autoscaling.enabled)) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
spec:
  minAvailable: {{ $svc.pdb.minAvailable }}
  selector:
    matchLabels:
      app: {{ .name }}
{{- end }}
{{- end -}}

{{/*
HTTPRoute through the API gateway. Context dict keys:
  root, name    as above
  backend       backend Service name
  port          backend Service port
  path          PathPrefix to match
  rewrite       optional ReplacePrefixMatch value; omit for no URLRewrite
  authLabel     optional value for the `auth` metadata label (private | public)
  sections      gateway listener sectionNames (default: ["https"])
*/}}
{{- define "lamassu.httproute" -}}
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: {{ .name }}
  namespace: {{ .root.Release.Namespace }}
  {{- with .authLabel }}
  labels:
    auth: {{ . | quote }}
  {{- end }}
spec:
  parentRefs:
    {{- range (.sections | default (list "https")) }}
    - name: eg
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
        - name: {{ .backend }}
          port: {{ .port }}
{{- end -}}
