{{- define "common.tolerations" }}
  {{- if .Values.customTolerations }}
{{ toYaml .Values.customTolerations }}
  {{- end }}
{{- end }}

