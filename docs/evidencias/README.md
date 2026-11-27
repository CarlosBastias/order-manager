# Evidencias EP3

Guarden aquí las capturas (PNG) con estos nombres y enlácenlas desde el README principal.
Marquen cada una cuando esté lista.

| Archivo | Qué debe mostrar | IE | Lista |
|---------|------------------|----|-------|
| `01-grafana-dashboard.png` | Dashboard completo con datos reales (tráfico, errores, CPU/memoria, pipeline) | IE3 | [ ] |
| `02-grafana-logs.png` | Panel de logs (Loki) con líneas INFO y al menos un WARN/ERROR | IE1 | [ ] |
| `03-prometheus-targets.png` | `http://localhost:9090/targets` con las réplicas en estado UP | IE1 | [ ] |
| `04-prometheus-alertas.png` | `http://localhost:9090/alerts` con las reglas cargadas (y una disparada si se prueba) | IE1 | [ ] |
| `05-pipeline-verde.png` | Run completo en verde (todos los jobs) en `main` | IE2 | [ ] |
| `06-k8s-prometheus.png` | Paso "Verificar monitoreo en el cluster" con las réplicas leídas | IE2 | [ ] |
| `07-eks-pods.png` | `kubectl get pods,svc,hpa` en EKS (si se despliega en AWS) | IE2 | [ ] |
| `08-auditoria-ok.png` | Reporte de `audit.py` aprobado (Summary del run) | IE5 | [ ] |
| `09-branch-protection.png` | Settings → Branches con los checks obligatorios | IE5 | [ ] |
| `10-bloqueo-auditoria.png` | Run manual con `simular_falla=true`: auditoría en rojo y jobs 3/4 saltados | IE6 | [ ] |
| `11-bloqueo-pr.png` | PR con una prueba/cobertura rota: checks en rojo y merge bloqueado | IE6 | [ ] |
