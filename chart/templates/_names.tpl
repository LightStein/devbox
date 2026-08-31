{{/*
Secret names default to <app_name>-<suffix> but can be overridden per user.
Kept in one place so the StatefulSet and the README cannot drift apart.
*/}}
{{- define "devbox.proxySecret" -}}
{{- default (printf "%s-proxy-secrets" .Values.app_name) .Values.secrets.proxy }}
{{- end }}

{{- define "devbox.sshSecret" -}}
{{- default (printf "%s-ssh" .Values.app_name) .Values.secrets.ssh }}
{{- end }}

{{- define "devbox.envSecret" -}}
{{- default (printf "%s-env-secrets" .Values.app_name) .Values.secrets.env }}
{{- end }}
