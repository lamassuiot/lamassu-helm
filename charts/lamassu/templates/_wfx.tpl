{{- define "lamassu.wfx.env" -}}
- name: WFX_STORAGE
  value: "postgres"
- name: WFX_CLIENT_HOST
  value: "0.0.0.0"
- name: WFX_CLIENT_PORT
  value: {{ .Values.services.wfx.clientPort | quote }}
- name: WFX_MGMT_HOST
  value: "0.0.0.0"
- name: WFX_MGMT_PORT
  value: {{ .Values.services.wfx.managementPort | quote }}
- name: WFX_LOG_FORMAT
  value: {{ .Values.services.wfx.logs.format | quote }}
- name: WFX_LOG_LEVEL
  value: {{ .Values.services.wfx.logs.level | quote }}
- name: PGHOST
  value: {{ .Values.postgres.hostname | quote }}
- name: PGPORT
  value: {{ .Values.postgres.port | quote }}
- name: PGUSER
  value: {{ .Values.postgres.username | quote }}
- name: PGPASSWORD
  value: {{ .Values.postgres.password | quote }}
- name: PGDATABASE
  value: {{ .Values.services.wfx.postgres.database | quote }}
- name: PGSSLMODE
  value: {{ .Values.services.wfx.postgres.sslmode | quote }}
{{- end -}}

{{- define "lamassu.wfx.containerPorts" -}}
- name: client
  containerPort: {{ .Values.services.wfx.clientPort }}
- name: management
  containerPort: {{ .Values.services.wfx.managementPort }}
{{- end -}}

{{- define "lamassu.wfx.svcPorts" -}}
- name: sbi
  port: {{ .Values.services.wfx.clientPort }}
  targetPort: {{ .Values.services.wfx.clientPort }}
  protocol: TCP
- name: nbi
  port: {{ .Values.services.wfx.managementPort }}
  targetPort: {{ .Values.services.wfx.managementPort }}
  protocol: TCP
{{- end -}}

{{- define "lamassu.wfx.livenessProbe" -}}
tcpSocket:
  port: {{ .Values.services.wfx.clientPort }}
initialDelaySeconds: 10
periodSeconds: 10
{{- end -}}

{{- define "lamassu.wfx.readinessProbe" -}}
tcpSocket:
  port: {{ .Values.services.wfx.clientPort }}
initialDelaySeconds: 3
periodSeconds: 5
{{- end -}}
