{{/* 命名约定: release 名 + chart 名, 避免不同 release 资源互相覆盖 */}}
{{- define "demo-chart.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-chart.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-chart.labels" -}}
helm.sh/chart: {{ include "demo-chart.name" . }}
app.kubernetes.io/name: {{ include "demo-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}

{{- define "demo-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "demo-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
