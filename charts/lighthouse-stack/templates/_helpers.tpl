{{/*
[Ref: 03_Phase4/08_一键部署工作流_设计] lighthouse-stack 通用标签
*/}}
{{- define "lighthouse-stack.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "lighthouse-stack.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "lighthouse-stack.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{- define "lighthouse-stack.labels" -}}
helm.sh/chart: {{ include "lighthouse-stack.name" . }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "lighthouse-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Bitnami PostgreSQL：Service / Secret 命名（与 subchart Release.Name = 父 Release.Name 一致）
*/}}
{{- define "lighthouse-stack.postgresqlServiceName" -}}
{{- printf "%s-postgresql" .Release.Name }}
{{- end }}

{{- define "lighthouse-stack.postgresqlSecretName" -}}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- printf "%s-postgresql" .Release.Name }}
{{- end }}
{{- end }}

{{- define "lighthouse-stack.postgresqlUserPasswordKey" -}}
{{- .Values.postgresql.auth.secretKeys.userPasswordKey | default "password" }}
{{- end }}

{{/*
Bitnami Redis master Service
*/}}
{{- define "lighthouse-stack.redisMasterServiceName" -}}
{{- printf "%s-redis-master" .Release.Name }}
{{- end }}

{{- define "lighthouse-stack.redisSecretName" -}}
{{- if .Values.redis.auth.existingSecret }}
{{- .Values.redis.auth.existingSecret }}
{{- else }}
{{- printf "%s-redis" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Bitnami ClickHouse：与 subchart Release.Name 一致时为 <Release>-clickhouse
*/}}
{{- define "lighthouse-stack.clickhouseServiceName" -}}
{{- printf "%s-clickhouse" .Release.Name }}
{{- end }}

{{- define "lighthouse-stack.clickhouseSecretName" -}}
{{- if .Values.clickhouse.auth.existingSecret }}
{{- .Values.clickhouse.auth.existingSecret }}
{{- else }}
{{- printf "%s-clickhouse" .Release.Name }}
{{- end }}
{{- end }}

{{- define "lighthouse-stack.clickhousePasswordKey" -}}
{{- .Values.clickhouse.auth.existingSecretKey | default "admin-password" }}
{{- end }}

{{/*
init-db ConfigMap 名称须与 postgresql.primary.initdb.scriptsConfigMap、deploy.sh --set 一致
*/}}
{{- define "lighthouse-stack.initSqlConfigMapName" -}}
{{- printf "%s-init-sql" .Release.Name }}
{{- end }}

{{/*
组件级 selector 标签（Deployment 与 Service 对齐）
*/}}
{{- define "lighthouse-stack.matchLabels" -}}
app.kubernetes.io/name: {{ include "lighthouse-stack.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
