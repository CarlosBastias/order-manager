# Fase 11 — Observabilidad (EP3: IE1 e IE3)

## Objetivo
Poder ver qué le pasa a la app mientras corre: métricas (uso, errores, CPU/memoria), logs y disponibilidad, y mostrarlo en un dashboard junto con las métricas del pipeline CI/CD.

## Arquitectura

```
app (N réplicas) --/actuator/prometheus--> Prometheus ----> Grafana (dashboard)
                                              ▲   │
pipeline (job 4c) --ci-metrics.prom--> Pushgateway   └--> reglas de alerta (alerts.yml)

contenedores --logs JSON (ECS)--> Promtail --> Loki ----> Grafana (paneles de logs)
```

Se levanta con:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
```

| Servicio | URL | Para qué |
|----------|-----|----------|
| Grafana | http://localhost:3000 (admin / admin) | Dashboard "order-manager - Observabilidad" |
| Prometheus | http://localhost:9090 | Métricas, targets (`/targets`) y alertas (`/alerts`) |
| Pushgateway | http://localhost:9091 | Recibe las métricas del pipeline |
| Loki | http://localhost:3100 | Almacén de logs (se consulta desde Grafana) |

## Métricas
- **Técnicas** (Actuator + Micrometer): `http_server_requests_seconds_*` (tráfico, latencia, errores por estado), `jvm_memory_*`, `process_cpu_usage`, `up` (disponibilidad por réplica).
- **De negocio** (código propio): `ordermanager_orders_placed_total`, `ordermanager_orders_status_changes_total{to}`, `ordermanager_errors_total{type,status}`.
- **Del pipeline** (job `4c`): `ci_test_coverage_percent`, `ci_tests_total`, `ci_tests_failed`, `ci_stage_duration_seconds{stage}`, `ci_pipeline_duration_seconds`, `ci_pipeline_success`.
- Para llevar las métricas del pipeline al dashboard: `.\scripts\sync-ci-metrics.ps1` (descarga el artefacto del último run y lo publica en el Pushgateway; con `-Loop` se repite cada 60 s).

## Logs
- En el perfil `docker` la app escribe los logs en **JSON formato ECS** (`logging.structured.format.console=ecs`).
- **Promtail** descubre los contenedores de compose por el socket de docker (montado en solo lectura), saca el nivel (`log.level`) y lo deja como etiqueta.
- **Loki** los guarda 7 días. En Grafana se consultan con LogQL, por ejemplo:
  - `{service="app"}` → todos los logs de la app (todas las réplicas)
  - `{service="app", level="ERROR"}` → solo errores
  - `sum by (level) (count_over_time({service="app"}[1m]))` → logs por nivel

## Dashboard (`observability/grafana/dashboards/order-manager.json`)
Se carga solo al levantar Grafana (provisioning). Filas:

| Fila | Qué muestra | Pide el enunciado |
|------|-------------|-------------------|
| Disponibilidad y tráfico | réplicas arriba, disponibilidad 1 h, req/s, % de 5xx, latencia p50/p95/p99 | disponibilidad, métricas de uso |
| Errores registrados | errores por tipo (últimos 5 min y acumulados) | errores registrados |
| Recursos | CPU y memoria heap por réplica | uso de CPU/memoria |
| Negocio | pedidos por minuto, cambios de estado | métricas de uso |
| Pipeline CI/CD | estado, cobertura, pruebas, tiempo de despliegue, duración por etapa, historial | tiempo de despliegue, cobertura de pruebas |
| Logs y alertas | alertas activas, errores en logs, logs por nivel, listado de WARN/ERROR y de todos los logs | logs |

## Alertas (`observability/prometheus/alerts.yml`)
`ServicioCaido`, `ReplicaCaida`, `ErroresServidor5xxAltos` (> 5 %), `LatenciaP95Alta` (> 1 s), `CpuAlta` (> 85 %), `PipelineFallido`, `CoberturaBajoMinimo` (< 60 %). Se ven en `/alerts` de Prometheus y el dashboard cuenta las que están disparadas. No hay Alertmanager (no hay a dónde enviar avisos en el laboratorio); el aviso fuera del dashboard es el issue automático del job 5.

## Cómo probar que funciona
1. Generar tráfico: `curl http://localhost:8080/api/orders` varias veces, crear pedidos con `POST`, y pedir uno que no existe (`/api/orders/999999`) para generar un error 404 y una línea WARN/ERROR.
2. Matar una réplica: `docker stop <contenedor de la app>` → baja "Réplicas disponibles" y se dispara `ReplicaCaida` al minuto.
3. Revisar `/targets`, `/alerts` y el panel de logs.
