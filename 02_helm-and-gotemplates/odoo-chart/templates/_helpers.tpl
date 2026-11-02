{{/*
Labels standards appliqués à toutes les ressources du chart.
Utilisation : {{- include "odoo.labels" . | nindent 4 }}
*/}}
{{- define "odoo.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels — utilisés dans spec.selector.matchLabels et podTemplates.
Plus restrictifs que les labels standards (pas de version).
Utilisation : {{- include "odoo.selectorLabels" . | nindent 6 }}
*/}}
{{- define "odoo.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Nom complet de la release (tronqué à 63 caractères — limite DNS Kubernetes).
Utilisation : {{ include "odoo.fullname" . }}
*/}}
{{- define "odoo.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
