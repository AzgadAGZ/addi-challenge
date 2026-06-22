{{/*
Expand the name of the chart.
*/}}
{{- define "addi-workload.fullname" -}}
{{- .Values.name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "addi-workload.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Values.name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- if .Values.owner }}
app.kubernetes.io/owner: {{ .Values.owner }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "addi-workload.selectorLabels" -}}
app: {{ .Values.name }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "addi-workload.namespace" -}}
{{- .Values.name }}
{{- end }}
