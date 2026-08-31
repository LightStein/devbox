{{/*
Naming and labels.

Every object is named for app_name rather than the release, so one release per
user gives you devbox-alice, devbox-bob and so on with no collisions.
*/}}
{{- define "helm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "helm.selectorLabels" -}}
app: {{ .Values.app_name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "helm.labels" -}}
helm.sh/chart: {{ include "helm.chart" . }}
{{ include "helm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Route hostname: <app_name>.<wildcard domain for this environment>.
*/}}
{{- define "ingress.hostName" -}}
{{- if eq .Values.env "prod" }}
{{- printf "%s.%s" .Values.app_name .Values.prod_hostname }}
{{- else if eq .Values.env "drc" }}
{{- printf "%s.%s" .Values.app_name .Values.drc_hostname }}
{{- else }}
{{- printf "%s.%s" .Values.app_name .Values.dev_hostname }}
{{- end }}
{{- end }}

{{/*
Replicas and resources per environment, falling back to the top-level values
when the environment has no block of its own.
*/}}
{{- define "replicas" -}}
{{- $env := index .Values .Values.env | default dict }}
{{- if hasKey $env "replicas" }}{{- $env.replicas }}{{- else }}{{- .Values.replicas }}{{- end }}
{{- end }}

{{- define "resources" -}}
{{- $env := index .Values .Values.env | default dict }}
{{- if $env.resources }}{{- toYaml $env.resources | nindent 12 }}
{{- else }}{{- toYaml .Values.resources | nindent 12 }}
{{- end }}
{{- end }}
