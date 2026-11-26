# Order Manager API — Pipeline CI/CD, observabilidad y cumplimiento

![CI/CD](https://github.com/CarlosBastias/order-manager/actions/workflows/ci-cd.yml/badge.svg)

Microservicio REST para gestionar pedidos de un e-commerce (crear pedidos, agregar ítems y moverlos por sus estados). Está hecho en **Spring Boot 4.0 + Java 17**, se empaqueta en un contenedor Docker y se despliega de forma automática con un pipeline de **GitHub Actions**.

Evaluación Parcial 2 (pipeline CI/CD) y Evaluación Parcial 3 (observabilidad, métricas y cumplimiento) — DOY0101 Ingeniería DevOps — Duoc UC.

> **EP3:** a lo anterior se agregó monitoreo con Prometheus, Grafana y Loki, despliegue en Kubernetes (kind y AWS EKS), dashboard con métricas del pipeline, auditoría de cumplimiento automatizada y mecanismos que detienen el pipeline ante fallas críticas. Las secciones nuevas son [Kubernetes](#kubernetes), [Observabilidad](#observabilidad), [Cumplimiento y auditoría](#cumplimiento-y-auditoría), [Demostración del bloqueo](#demostración-del-bloqueo), [Decisiones técnicas](#decisiones-técnicas) y [Evidencias](#evidencias).

---

## Integrantes

| Nombre | GitHub | Parte principal |
|--------|--------|-----------------|
| Fabián Andrés Sánchez Vargas | [@pisKyxD](https://github.com/pisKyxD) | Pipeline CI/CD, Dependabot, SonarCloud/Snyk, documentación |
| Carlos Bastias | [@CarlosBastias](https://github.com/CarlosBastias) | Microservicio, Dockerfile, perfil docker, docker-compose |

---

## Tabla de contenido

1. [Tecnologías](#tecnologías)
2. [Endpoints](#endpoints)
3. [Cómo ejecutar en local](#cómo-ejecutar-en-local)
4. [Cómo ejecutar con Docker](#cómo-ejecutar-con-docker)
5. [Pipeline CI/CD por etapas](#pipeline-cicd-por-etapas)
6. [Bloqueos y alertas](#bloqueos-y-alertas)
7. [Trazabilidad](#trazabilidad)
8. [Calidad](#calidad)
9. [Orquestación de contenedores](#orquestación-de-contenedores)
10. [Kubernetes](#kubernetes)
11. [Observabilidad](#observabilidad)
12. [Cumplimiento y auditoría](#cumplimiento-y-auditoría)
13. [Demostración del bloqueo](#demostración-del-bloqueo)
14. [Decisiones técnicas](#decisiones-técnicas)
15. [Evidencias](#evidencias)
16. [Configuración necesaria en GitHub](#configuración-necesaria-en-github)
17. [Estructura del proyecto](#estructura-del-proyecto)
18. [Uso de IA](#uso-de-ia)
19. [Reflexiones individuales](#reflexiones-individuales)

---

## Tecnologías

| Área | Herramienta |
|------|-------------|
| Lenguaje / framework | Java 17, Spring Boot 4.0.9 (Web MVC, Data JPA, Validation, Actuator) |
| Base de datos | H2 en memoria (local y pruebas), PostgreSQL 16 (Docker) |
| Pruebas | JUnit 5, Mockito, MockMvc (`@WebMvcTest` + `@MockitoBean`) |
| Cobertura | JaCoCo 0.8.13 |
| Contenedores | Docker (multi-stage), Docker Compose |
| CI/CD | GitHub Actions |
| Calidad de código (SAST) | SonarCloud + Quality Gate |
| Seguridad de dependencias (SCA) | Snyk, Dependabot, Dependency Review |
| Seguridad de la imagen | Snyk Container |
| Orquestación (EP3) | Kubernetes: kind en el pipeline y AWS EKS (opcional), HPA, PodDisruptionBudget |
| Métricas (EP3) | Micrometer + Prometheus, Pushgateway (métricas del pipeline) |
| Logs (EP3) | Logs JSON (ECS) → Promtail → Loki |
| Dashboards y alertas (EP3) | Grafana (provisionado por código), reglas de alerta de Prometheus |
| Cumplimiento (EP3) | `scripts/audit.py`, protección de rama, SonarCloud, Snyk |

---

## Endpoints

Base: `/api/orders`

| Método | Ruta | Qué hace |
|--------|------|----------|
| GET | `/api/orders` | Lista todos los pedidos |
| GET | `/api/orders/{id}` | Busca un pedido por id |
| GET | `/api/orders/status/{status}` | Lista pedidos por estado |
| POST | `/api/orders` | Crea un pedido |
| POST | `/api/orders/{id}/items` | Agrega un ítem al pedido |
| PUT | `/api/orders/{id}/confirm` | PENDING → CONFIRMED |
| PUT | `/api/orders/{id}/ship` | CONFIRMED → SHIPPED |
| PUT | `/api/orders/{id}/deliver` | SHIPPED → DELIVERED |
| PUT | `/api/orders/{id}/cancel` | Cancela (menos si ya está DELIVERED) |
| DELETE | `/api/orders/{id}` | Elimina el pedido |
| GET | `/actuator/health` | Estado de la app (lo usa el healthcheck) |

Estados: `PENDING → CONFIRMED → SHIPPED → DELIVERED`, y desde cualquiera menos `DELIVERED` se puede pasar a `CANCELLED`.

Ejemplo para crear un pedido:

```json
POST /api/orders
{
  "customerName": "Juan Pérez",
  "items": [
    { "productName": "Teclado", "quantity": 2, "unitPrice": 15000 }
  ]
}
```

---

## Cómo ejecutar en local

Requisitos: **Java 17** y **Maven 3.9+**.

```bash
# clonar
git clone https://github.com/CarlosBastias/order-manager.git
cd order-manager

# correr pruebas + reporte de cobertura
mvn clean verify

# levantar la app (perfil por defecto, H2 en memoria)
mvn spring-boot:run
```

- API: http://localhost:8098/api/orders
- Consola H2: http://localhost:8098/h2-console (JDBC URL `jdbc:h2:mem:orderdb`, usuario `sa`, sin clave)
- Health: http://localhost:8098/actuator/health
- Reporte de cobertura: abrir `target/site/jacoco/index.html`

---

## Cómo ejecutar con Docker

Requisitos: **Docker** y **Docker Compose v2**.

```bash
# construir la imagen y levantar app + postgres
docker compose up -d --build

# ver estado (las dos deberían quedar "healthy")
docker compose ps

# logs de la app
docker compose logs -f app

# probar
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/orders

# bajar todo (con -v se borra también el volumen de la base)
docker compose down -v
```

La clave de PostgreSQL se toma de la variable `POSTGRES_PASSWORD`. Si no existe se usa la de desarrollo. Para cambiarla en local se puede crear un archivo `.env` (está en el `.gitignore`):

```env
POSTGRES_PASSWORD=una_clave_segura
```

Solo la imagen, sin compose:

```bash
docker build -t order-manager:local .
docker run --rm -p 8080:8080 order-manager:local   # usa el perfil por defecto (H2)
```

---

## Pipeline CI/CD por etapas

Archivo: [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml)

**Se ejecuta con:** push a `main` o `dev`, Pull Request hacia `main` o `dev`, y manualmente (`workflow_dispatch`). En las ramas `feature/*` el pipeline corre a través del Pull Request.

```
                 ┌──────────────────────────┐
                 │ 1. Build y pruebas       │  mvn clean verify + JaCoCo + cobertura mínima
                 └────────────┬─────────────┘
     ┌────────────────┬───────┴────────┬──────────────────────┐
     ▼                ▼                ▼                      ▼
┌──────────┐  ┌──────────────┐  ┌───────────────┐  ┌────────────────────────┐
│2. Snyk   │  │2. SonarCloud │  │2b. Dependency │  │2c. Auditoría           │
│  (SCA)   │  │ Quality Gate │  │ Review (PR)   │  │ (scripts/audit.py)     │
└────┬─────┘  └──────┬───────┘  └───────────────┘  └───────────┬────────────┘
     └───────┬───────┴─────────────────────────────────────────┘
             ▼
┌──────────────────────────┐
│ 3. Imagen Docker         │  build + labels OCI + Snyk Container
└────────────┬─────────────┘
   ┌─────────┼───────────────────┐
   ▼         ▼                   ▼
┌────────┐ ┌─────────────────┐ ┌──────────────────────────┐
│4. Docker│ │4b. Kubernetes   │ │4d. AWS EKS (opcional,    │
│ compose │ │ (kind) + Prom.  │ │ solo main + variables)   │
└────┬───┘ └───────┬─────────┘ └────────────┬─────────────┘
     └─────────────┴────────────────────────┘
             ▼
┌──────────────────────────┐
│ 4c. Métricas del pipeline│  ci-metrics.prom → Pushgateway → Grafana
└──────────────────────────┘
             ▼ (solo si algo falló en un push)
┌──────────────────────────┐
│ 5. Alerta                │  abre un issue automático
└──────────────────────────┘
```

### 1. Build y pruebas (`build-test`)
- `actions/checkout` con historial completo (Sonar lo necesita para saber qué código es nuevo).
- `actions/setup-java` con **Temurin 17** y caché de Maven para que no descargue todo cada vez.
- `mvn -B clean verify`: compila, corre las **26 pruebas** (16 de `OrderServiceTest`, 8 de `OrderControllerTest` y 2 de `OrderMetricsTest`) y genera el reporte de JaCoCo. **Si una prueba falla, Maven termina con error y el pipeline se detiene ahí.**
- Revisa la cobertura de líneas leyendo `jacoco.csv`; si queda bajo el mínimo (`MIN_COVERAGE`, 60%) el job falla.
- Sube como artefactos: reportes de Surefire y JaCoCo, el `.jar`, y las clases compiladas para el job de Sonar.

### 2. Seguridad de dependencias con Snyk (`security-scan`)
- Instala Snyk CLI y se autentica con el secret `SNYK_TOKEN`.
- Genera `snyk-report.json` y lo deja como artefacto (evidencia).
- `snyk test --severity-threshold=high`: **si hay vulnerabilidades altas o críticas en las dependencias del `pom.xml`, falla.**
- Respeta las excepciones documentadas en el archivo [`.snyk`](.snyk) (ver [Bloqueos y alertas](#bloqueos-y-alertas)).
- En `main` además corre `snyk monitor`, que registra el proyecto en Snyk y manda correos cuando aparecen vulnerabilidades nuevas.

### 2. Calidad de código con SonarCloud (`code-analysis`)
- Descarga las clases compiladas y los reportes del job 1 (no vuelve a compilar).
- Corre el scanner con la configuración de [`sonar-project.properties`](sonar-project.properties): fuentes, pruebas, reporte de JaCoCo y resultados de JUnit.
- `sonar.qualitygate.wait=true` hace que el paso espere el resultado del **Quality Gate**; **si no pasa, el job falla.**
- El plan gratis de SonarCloud solo analiza `main` y los Pull Requests. En un push a `dev` el escaneo no corre y queda un aviso en el run; ese código ya pasó el Quality Gate en su Pull Request antes de llegar a `dev`.

### 2b. Dependency Review (`dependency-review`, solo en PR)
- Compara las dependencias del PR contra la rama destino y **falla si se agrega alguna con vulnerabilidad alta**. Deja un comentario en el PR cuando falla.

### 3. Imagen Docker (`docker-build`)
- Solo corre si pasaron **pruebas, Snyk y Quality Gate**.
- Construye la imagen con Buildx usando el `Dockerfile` multi-stage, con caché de GitHub Actions.
- La imagen queda con dos tags: `order-manager:<sha del commit>` y `order-manager:latest`.
- Se le agregan labels OCI (`revision`, `source`, `version`) con el commit y el número de ejecución.
- **Snyk Container** escanea la imagen ya construida (sistema base + JRE); **falla si hay vulnerabilidades críticas**.
- La imagen se exporta con `docker save` y se sube como artefacto, para desplegar exactamente la misma que se escaneó.

### 4. Despliegue simulado (`deploy`)
- Usa el environment de GitHub **`simulated-production`**, así cada despliegue queda registrado en la pestaña *Environments / Deployments*.
- Carga la imagen del job anterior (`docker load`).
- La clave de PostgreSQL sale del secret `POSTGRES_PASSWORD` o, si no existe, se genera una al azar (y se oculta en los logs).
- `docker compose up -d --no-build --wait`: levanta PostgreSQL y la app y **espera a que los dos healthchecks estén OK**.
- **Smoke test** contra la app desplegada: health `UP`, crear un pedido (debe quedar `PENDING`), consultarlo, confirmarlo (debe quedar `CONFIRMED`) y listar.
- Si algo falla se muestran los logs de los contenedores. Al final siempre se hace `docker compose down -v`.
- Deja un resumen en la pestaña *Summary* del run con commit, rama, autor, tag de la imagen y link al run.

### 2c. Auditoría de cumplimiento (`audit`, EP3)
- Ejecuta [`scripts/audit.py`](scripts/audit.py): revisa secretos escritos en el código, Dockerfile, manifiestos de Kubernetes, Docker Compose y permisos del workflow (reglas en [Cumplimiento y auditoría](#cumplimiento-y-auditoría)).
- **Si encuentra un ERROR, el job falla y no se construye la imagen** (el job 3 depende de este).
- Deja el reporte en el *Summary* y como artefacto `audit-report`.

### 4b. Despliegue en Kubernetes (`deploy-k8s`, EP3)
- Crea un cluster **kind** en el runner, carga la misma imagen, aplica `k8s/`, espera los rollouts, hace smoke test (incluye las métricas), escala a 3 réplicas y **verifica que Prometheus, desplegado dentro del cluster, lea todas las réplicas**. Si no las lee, el despliegue falla.

### 4c. Métricas del pipeline (`ci-metrics`, EP3)
- Calcula cobertura, pruebas ejecutadas/fallidas, duración de cada etapa (incluido el tiempo de despliegue) y resultado del pipeline, y los deja como `ci-metrics.prom` (formato Prometheus). Corre siempre, también cuando el pipeline falla, para registrar los fallos.
- `scripts/sync-ci-metrics.ps1` los publica en el Pushgateway y aparecen en el dashboard de Grafana.

### 4d. Despliegue en AWS EKS (`deploy-eks`, EP3)
- Opcional: solo corre en push a `main` si el repo tiene la variable `EKS_CLUSTER_NAME`. Sube la imagen a ECR, aplica `k8s/` en EKS (login por OIDC, sin llaves) y repite la verificación de Prometheus. Pasos de configuración en [fase 12](docs/fases/fase-12-kubernetes-y-eks.md).

### 5. Alerta de falla (`notify-failure`)
- Si cualquier etapa falla en un **push** a `main` o `dev`, marca el run con un error visible y deja en el *Summary* una tabla con el resultado de cada job.
- Además abre un **issue automático** con el commit, el autor y el link al run que falló. Si el repo tuviera los Issues desactivados, no se cae: deja un aviso en el log.

---

## Bloqueos y alertas

| Qué se revisa | Dónde | Qué pasa si falla |
|---------------|-------|-------------------|
| Pruebas unitarias / de controlador | `mvn clean verify` (job 1) | Se detiene todo el pipeline |
| Cobertura mínima (60% de líneas) | Job 1 | Se detiene todo el pipeline |
| Vulnerabilidades high/critical en dependencias | Snyk (job 2) | No se construye la imagen ni se despliega |
| Quality Gate de SonarCloud | Job 2 | No se construye la imagen ni se despliega |
| Dependencias nuevas con vulnerabilidad alta (PR) | Dependency Review | El PR queda en rojo y no se puede mergear |
| Vulnerabilidades críticas en la imagen | Snyk Container (job 3) | No se despliega |
| App no levanta / healthcheck / smoke test | Job 4 | El despliegue queda fallido y se ven los logs |
| Auditoría de cumplimiento (secretos, Dockerfile, k8s, compose, workflow) | `audit.py` (job 2c) | No se construye la imagen ni se despliega |
| Prometheus no lee las réplicas desplegadas en Kubernetes | Job 4b (y 4d) | El despliegue falla |
| Falta una métrica esperada en `/actuator/prometheus` | Job 4 | El despliegue falla |
| Cualquier falla en push a `main` o `dev` | Job 5 | Se abre un issue de alerta |
| Vulnerabilidades nuevas después del deploy | `snyk monitor` + alertas de Dependabot | Correo de Snyk / alerta en la pestaña Security |

**Excepciones aceptadas (archivo [`.snyk`](.snyk))**: cuando una vulnerabilidad no tiene parche disponible y no aplica al proyecto, se registra en `.snyk` con el motivo y una fecha de vencimiento. Hoy hay una sola: `SNYK-JAVA-ORGGLASSFISHJAXB-20883142` (XXE en `jaxb-core`, dependencia interna de Hibernate). No tiene versión corregida y la API no procesa XML, solo JSON. Vence el 31-01-2027; ahí Snyk vuelve a bloquear y se revisa de nuevo. Todas las demás vulnerabilidades altas o críticas siguen bloqueando el pipeline.

**Ejemplo real del bloqueo funcionando**: en las primeras ejecuciones Snyk detuvo el pipeline por vulnerabilidades altas y críticas en Spring Boot 3.3.4 (Tomcat, spring-web, Jackson, logback). Primero se subió a 3.5.16, pero esa rama ya no recibe parches gratuitos y seguían 26 vulnerabilidades; por eso se migró a **Spring Boot 4.0.9**, lo que dejó una sola vulnerabilidad sin parche (la excepción de arriba).

Para que el bloqueo aplique también al **merge**, en GitHub hay que activar la protección de rama (ver [Configuración necesaria](#configuración-necesaria-en-github)).

---

## Trazabilidad

Cómo se puede seguir un cambio desde el commit hasta el despliegue:

1. **Commit → run**: cada push o PR dispara un run del pipeline; en la pestaña *Actions* se ve qué commit, qué rama y quién lo hizo.
2. **Run → imagen**: la imagen se etiqueta con el **SHA del commit** (`order-manager:<sha>`) y lleva las labels `org.opencontainers.image.revision` y `org.opencontainers.image.source`. Con `docker image inspect` se sabe de qué commit salió.
3. **Imagen → despliegue**: el job de deploy usa la **misma imagen** que se construyó y escaneó (se pasa como artefacto, no se vuelve a construir) y queda registrado en el environment `simulated-production`.
4. **Evidencias por run**: artefactos descargables con los reportes de pruebas, la cobertura, el reporte de Snyk y el `.jar`, más el resumen del despliegue.
5. **Pull Requests**: los cambios entran por PR, el PR muestra el estado de cada job, y Dependabot también abre sus actualizaciones como PR, así que todo cambio de dependencias queda con su historial.
6. **Fallas**: cada falla en push a `main` o `dev` queda marcada en el run y genera un issue con el link exacto al run.
7. **Excepciones de seguridad**: las vulnerabilidades aceptadas quedan versionadas en `.snyk`, con motivo, fecha de creación y vencimiento.

---

## Calidad

- **Pruebas automatizadas**: 26 pruebas (JUnit 5 + Mockito + MockMvc) que cubren lo crítico del negocio: crear pedidos, agregar ítems, las transiciones de estado válidas, las inválidas (por ejemplo cancelar un pedido ya entregado o ya cancelado, o agregar ítems a un pedido que no está PENDING) y los códigos HTTP (200, 201, 204, 400, 404, 409).
- **Cobertura**: JaCoCo genera el reporte en cada run; el pipeline exige mínimo 60% de líneas y SonarCloud además la mide sobre el código nuevo.
- **Quality Gate**: se usa el gate de SonarCloud (*Sonar way*), que revisa bugs, vulnerabilidades, code smells, duplicación, security hotspots y cobertura del código nuevo. Si no pasa, no hay despliegue.
- **Dependencias**: Dependabot revisa cada semana Maven, GitHub Actions y las imágenes base de Docker, y Snyk revisa vulnerabilidades en cada run. Por los hallazgos de Snyk el proyecto se actualizó de Spring Boot 3.3.4 a 4.0.9 y el driver de PostgreSQL a 42.7.14.
- **Imagen**: multi-stage (la imagen final solo lleva el JRE y el `.jar`), corre con un **usuario no root**, y se escanea con Snyk Container antes de desplegar.
- **Secretos**: tokens y claves van en *GitHub Secrets*, nunca en el código; los permisos del `GITHUB_TOKEN` son de solo lectura por defecto y cada job pide solo lo que necesita.

---

## Orquestación de contenedores

Se usa **Docker Compose** ([`docker-compose.yml`](docker-compose.yml)) con dos servicios en una red bridge propia (`order-net`):

| Servicio | Imagen | Detalle |
|----------|--------|---------|
| `db` | `postgres:16` | Volumen `pg_data` para persistir datos, healthcheck con `pg_isready`, puerto solo en `127.0.0.1`, límite 1 CPU / 512 MB |
| `app` | `order-manager:${IMAGE_TAG}` | Perfil `docker`, espera a que la db esté *healthy* (`depends_on: condition: service_healthy`), healthcheck contra `/actuator/health`, límite 1 CPU / 768 MB, `restart: unless-stopped` |

Puntos importantes:
- **Orden de arranque real**: `depends_on` con `service_healthy` hace que la app parta solo cuando PostgreSQL ya acepta conexiones, no apenas se crea el contenedor.
- **Recursos**: los límites de CPU y memoria evitan que un servicio se coma la máquina. La JVM usa `-XX:MaxRAMPercentage=75.0`, o sea, se ajusta sola al límite de memoria del contenedor.
- **Auto-recuperación**: con `restart: unless-stopped` si un contenedor se cae, Docker lo vuelve a levantar.
- **Misma config en local y en el pipeline**: el despliegue simulado usa este mismo archivo, solo que con `--no-build` y el tag del commit.

---

## Kubernetes

Manifiestos en [`k8s/`](k8s/) (se aplican con `kubectl apply -k k8s/`):

| Archivo | Qué define |
|---------|------------|
| `00-namespace.yaml` / `01-configmap.yaml` | Namespace `order-manager` y configuración de la app |
| `02-postgres.yaml` | PostgreSQL con su Service |
| `03-app.yaml` | API: 2 réplicas, rolling update sin caída, probes startup/liveness/readiness, requests y limits, usuario no root, filesystem de solo lectura, anotaciones `prometheus.io/*` |
| `04-hpa.yaml` | Autoescalado de 2 a 5 réplicas (CPU 70 %, memoria 85 %) y PodDisruptionBudget |
| `05-prometheus.yaml` | Prometheus dentro del cluster con permisos mínimos (Role solo para leer pods del namespace) |

- **En el pipeline** el despliegue corre en un cluster kind efímero (job 4b). **En la nube**, el job 4d lo aplica en AWS EKS cuando está configurado (ver [fase 12](docs/fases/fase-12-kubernetes-y-eks.md)).
- Prometheus descubre las réplicas por las anotaciones del pod, así que las que crea el HPA se monitorean solas.

---

## Observabilidad

Se levanta sobre el docker-compose del proyecto:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
# Grafana    http://localhost:3000   (admin / admin)  -> dashboard "order-manager - Observabilidad"
# Prometheus http://localhost:9090   (/targets y /alerts)
```

```
app (réplicas) --/actuator/prometheus--> Prometheus --> Grafana
pipeline --ci-metrics.prom--> Pushgateway --> Prometheus
contenedores --logs JSON--> Promtail --> Loki --> Grafana
```

| Qué se observa | Cómo | Dónde se ve |
|----------------|------|-------------|
| Uso: peticiones/s, latencia p50/p95/p99, pedidos creados, cambios de estado | Micrometer + métricas propias (`ordermanager_*`) | Dashboard, filas *Disponibilidad y tráfico* y *Negocio* |
| Errores | `http_server_requests` (5xx) y `ordermanager_errors_total{type,status}` | Fila *Errores registrados* |
| Disponibilidad | métrica `up` de cada réplica | Réplicas disponibles, disponibilidad 1 h, `/targets` |
| CPU y memoria | `process_cpu_usage`, `jvm_memory_*` | Fila *Recursos* |
| Logs | JSON (ECS) → Promtail → Loki; filtrables por nivel y réplica | Fila *Logs y alertas* |
| Pipeline: cobertura, pruebas, tiempo de despliegue, duración por etapa | job 4c → Pushgateway | Fila *Pipeline CI/CD* |
| Alertas | `observability/prometheus/alerts.yml` (servicio caído, réplica caída, 5xx > 5 %, p95 > 1 s, CPU > 85 %, pipeline fallido, cobertura < 60 %) | Prometheus `/alerts` y contador en el dashboard |

Detalle completo, consultas LogQL y cómo probar cada panel: [fase 11](docs/fases/fase-11-observabilidad.md).

Para llevar las métricas del último pipeline al dashboard: `.\scripts\sync-ci-metrics.ps1` (requiere GitHub CLI; con `-Loop` se repite cada 60 s). Esta sincronización es manual porque Grafana corre en la máquina local y no en la nube.

---

## Cumplimiento y auditoría

| Política | Herramienta | Si no se cumple |
|----------|-------------|-----------------|
| Quality Gate de calidad y seguridad del código | SonarCloud | no se construye la imagen |
| Sin vulnerabilidades altas/críticas en dependencias | Snyk (excepciones con vencimiento en `.snyk`) | no se construye la imagen |
| Sin dependencias nuevas vulnerables en PR | Dependency Review | PR en rojo |
| Cobertura mínima 60 % y pruebas en verde | JaCoCo + JUnit | se detiene el pipeline |
| Auditoría propia: secretos, Dockerfile, k8s, compose, workflow | `scripts/audit.py` | no se construye la imagen |
| PR obligatorio, checks en verde y 1 aprobación para entrar a `main` | Branch protection (`scripts/branch-protection.sh`) | no se puede mergear |

Reglas de `audit.py` (ERROR detiene el pipeline, ADVERTENCIA solo informa): sin secretos escritos en el código ni `.env` versionado; Dockerfile sin root y con versiones fijas; en Kubernetes requests/limits, probes y contenedor propio sin root ni escalada de privilegios; en Compose límite de memoria, base de datos sin exponer y `docker.sock` solo en solo lectura; en el workflow permisos mínimos y acciones con versión fija. La tabla completa está en la [fase 13](docs/fases/fase-13-cumplimiento-y-bloqueo.md).

Advertencias que se aceptan hoy (informadas, no bloquean): PostgreSQL en Kubernetes corre con la imagen oficial, que arranca como root, y Promtail monta el socket de docker en solo lectura (necesario para descubrir contenedores; solo para el entorno local).

---

## Demostración del bloqueo

Cómo se comprueba que ante una falla crítica el pipeline se detiene (pasos completos en la [fase 13](docs/fases/fase-13-cumplimiento-y-bloqueo.md)):

1. **Falla de seguridad simulada, un clic:** `gh workflow run ci-cd.yml --ref dev -f simular_falla=true`. El job 2c detecta un secreto escrito en el código, falla, y los jobs 3, 4, 4b y 4d quedan saltados.
2. **Falla de calidad en un PR:** un PR con una prueba rota deja el job 1 en rojo, todo lo demás saltado y el merge bloqueado por la protección de rama.
3. **Falla real documentada (EP2):** Snyk detuvo el pipeline por vulnerabilidades en Spring Boot 3.3.4 (ver [Bloqueos y alertas](#bloqueos-y-alertas)).

Enlaces a los runs: _completar con los links de GitHub Actions de cada demostración_

---

## Decisiones técnicas

> **Completar por el equipo, sin IA.** Esta sección es una justificación técnica propia (IE4): la tabla indica qué señal da cada herramienta y dónde se ve; la columna de decisión la escriben ustedes con lo que realmente observaron y decidieron.

| Señal | Dónde se ve | Decisión técnica que permitió (o permitiría) |
|-------|-------------|-----------------------------------------------|
| Latencia p95 y % de errores 5xx | Dashboard, fila *Disponibilidad y tráfico* | _completar_ |
| CPU y memoria por réplica | Dashboard, fila *Recursos* y HPA | _completar_ |
| Logs WARN/ERROR por réplica | Dashboard, fila *Logs y alertas* | _completar_ |
| Cobertura y pruebas fallidas por run | Dashboard, fila *Pipeline CI/CD* | _completar_ |
| Tiempo de despliegue por etapa | Dashboard, *Duración por etapa del pipeline* | _completar_ |
| Reporte de `audit.py` y Quality Gate | *Summary* del run y SonarCloud | _completar_ |

Cómo se integran las herramientas en el pipeline: Sonar, Snyk, Dependency Review y la auditoría **bloquean** antes de construir la imagen; Prometheus, Grafana y Loki **observan** lo desplegado; el job 4c **conecta** las dos cosas llevando los resultados del pipeline al mismo dashboard que las métricas de la app.

---

## Evidencias

Capturas en [`docs/evidencias/`](docs/evidencias/) (lista de qué debe mostrar cada una en ese directorio):

_completar con las imágenes cuando estén guardadas, por ejemplo:_ `![Dashboard](docs/evidencias/01-grafana-dashboard.png)`

---

## Configuración necesaria en GitHub

Esto se hace una sola vez en el repo:

1. **SonarCloud**
   - Entrar a https://sonarcloud.io con GitHub, importar el repositorio.
   - En el proyecto: *Administration → Analysis Method* → **desactivar Automatic Analysis** (si no, choca con el análisis del pipeline).
   - Copiar la *Project Key* y la *Organization Key* en `sonar-project.properties`.
   - Generar un token en *My Account → Security* y guardarlo en GitHub como secret `SONAR_TOKEN`.
2. **Snyk**
   - Crear cuenta en https://snyk.io, ir a *Account settings* y copiar el token.
   - Guardarlo en GitHub como secret `SNYK_TOKEN`.
3. **Secrets** (*Settings → Secrets and variables → Actions*)
   - `SONAR_TOKEN` (obligatorio)
   - `SNYK_TOKEN` (obligatorio)
   - `POSTGRES_PASSWORD` (opcional, si no está se genera una al azar en cada deploy)
4. **Seguridad del repo** (*Settings → Code security*): activar *Dependency graph*, *Dependabot alerts* y *Dependabot security updates*.
5. **Protección de la rama `main`** (*Settings → Branches → Add rule*):
   - *Require a pull request before merging*
   - *Require status checks to pass* → marcar `1. Build y pruebas (JUnit + JaCoCo)`, `2. Seguridad de dependencias (Snyk)`, `2. Calidad de código (SonarCloud)`, `2c. Auditoría de cumplimiento`, `3. Imagen Docker + escaneo de seguridad` y `4b. Despliegue en Kubernetes (kind)`.
   - Se puede aplicar todo de una vez con `bash scripts/branch-protection.sh` (requiere `gh` y ser administrador del repo).
6. **AWS EKS (opcional)**: variables `EKS_CLUSTER_NAME`, `AWS_REGION`, `AWS_ROLE_ARN` y `ECR_REPOSITORY` en *Settings → Secrets and variables → Actions → Variables* (pasos en [fase 12](docs/fases/fase-12-kubernetes-y-eks.md)). Sin ellas el job 4d se salta.

---

## Estructura del proyecto

```
.
├── .github/
│   ├── dependabot.yml           # actualizaciones semanales (maven, actions, docker)
│   └── workflows/ci-cd.yml      # pipeline CI/CD
├── docs/fases/                  # documentación de cada fase del proyecto (11 a 13 = EP3)
├── docs/evidencias/             # capturas de evidencia de la EP3
├── k8s/                         # manifiestos de Kubernetes (app, postgres, HPA, Prometheus)
├── observability/               # Prometheus (+ alertas), Grafana (dashboard), Loki, Promtail, Istio/Kiali
├── scripts/                     # audit.py, sync-ci-metrics.ps1, branch-protection.sh, istio-kiali-kind.ps1
├── docker-compose.observability.yml  # Prometheus + Pushgateway + Loki + Promtail + Grafana
├── src/
│   ├── main/java/com/example/ordermanager/
│   │   ├── controller/          # OrderController (endpoints REST)
│   │   ├── dto/                 # CreateOrderRequest, AddItemRequest
│   │   ├── exception/           # excepciones + GlobalExceptionHandler
│   │   ├── model/               # Order, OrderItem, OrderStatus
│   │   ├── repository/          # OrderRepository (JPA)
│   │   └── service/             # OrderService (reglas de negocio)
│   ├── main/resources/
│   │   ├── application.properties          # perfil por defecto (H2, puerto 8098)
│   │   └── application-docker.properties   # perfil docker (PostgreSQL, puerto 8080)
│   └── test/java/...            # OrderServiceTest, OrderControllerTest
├── Dockerfile                   # multi-stage: maven build -> JRE, usuario no root
├── docker-compose.yml           # app + postgres
├── sonar-project.properties     # configuración de SonarCloud
├── .snyk                        # excepciones de seguridad aceptadas (con motivo y vencimiento)
└── pom.xml
```

Documentación por fase (EP3: [Fase 11 – Observabilidad](docs/fases/fase-11-observabilidad.md) · [Fase 12 – Kubernetes y EKS](docs/fases/fase-12-kubernetes-y-eks.md) · [Fase 13 – Cumplimiento y bloqueo](docs/fases/fase-13-cumplimiento-y-bloqueo.md)): [Fase 06 – Contenedores](docs/fases/fase-06-contenedores.md) · [Fase 07 – Perfil Docker](docs/fases/fase-07-perfil-docker.md) · [Fase 08 – Orquestación](docs/fases/fase-08-orquestacion.md) · [Fase 09 – CI/CD](docs/fases/fase-09-cicd.md) · [Fase 10 – Documentación](docs/fases/fase-10-documentacion.md)

---

## Uso de IA

Declaración según las indicaciones de la evaluación ([bibliotecas.duoc.cl/ia](https://bibliotecas.duoc.cl/ia)):

| Herramienta | Para qué se usó | Cómo lo validamos |
|-------------|-----------------|-------------------|
| Claude (Anthropic) | Apoyo para armar la estructura del workflow de GitHub Actions, la configuración de Dependabot, SonarCloud y Snyk, interpretar los reportes de Snyk y hacer la migración a Spring Boot 4, y para ordenar y redactar este README y los documentos de fases 06 a 10 | Revisamos cada archivo, lo comparamos con el material del curso, probamos el pipeline en GitHub Actions y ajustamos lo que no calzaba con nuestro proyecto |
| Claude (Anthropic) — EP3 | Apoyo para la configuración de Loki/Promtail, las reglas de alerta, los paneles de logs del dashboard, el job de EKS, las reglas de `audit.py`, los scripts de protección de rama y la demostración de bloqueo, y para ordenar la documentación (fases 11 a 13 y las secciones nuevas del README) | _completar con cómo lo validaron: levantaron el compose, vieron los paneles, corrieron el pipeline y la demostración, etc._ |

La IA **no** se usó para las reflexiones individuales ni para las conclusiones.

Referencia:
> Anthropic. (2026). *Claude* (versión Opus) [Modelo de lenguaje grande]. https://claude.ai

---

## Reflexiones individuales

> Escritas por cada integrante, sin uso de IA.

### Fabián Sánchez

**¿Qué aprendí?**

Aprendí a automatizar todo el proceso de build, pruebas, seguridad y despliegue con GitHub Actions. También entendí mejor cómo funcionan herramientas como Snyk, SonarCloud y Dependabot, además de los conceptos básicos de escalabilidad con Nginx y Kubernetes.

**¿Qué me costó?**

Claramente lo q mas me complicó fue lidiar con las vulnerabilidades q iba detectando Snyk. Tuve q actualizar Spring Boot varias veces hasta llegar a 4.0.9, lo cual me obligó a ajustar las pruebas del controlador para q fueran compatibles con esa versión.

**¿Cuál fue mi aporte?**

Me encargué del pipeline CI/CD completo en `.github/workflows/ci-cd.yml`.

### Carlos Bastias

**¿Qué aprendí?**

Aprendí a empaquetar la app con Docker multi-stage, a correrla con un usuario sin permisos de root y a levantar app + base de datos juntos con docker-compose. También aprendí a usar los perfiles de Spring para separar la configuración entre local y Docker. 

**¿Qué me costó?**

Lo que más me complicó fue el orden de arranque. Al principio la app intentaba conectarse a PostgreSQL antes de que estuviera listo. Tuve que usar depends_on con condition: service_healthy y armar un healthcheck para la app, ya que la imagen JRE no trae curl. 

**¿Cuál fue mi aporte?**

Me encargué del Dockerfile, .dockerignore, docker-compose.yml (app + Postgres, red order-net, volumen pg_data, healthchecks, límites y restart: unless-stopped), y application-docker.properties. Todo esto lo desarrollé en mi rama feature/docker-orquestacion e integré a dev para dejarlo listo para el despliegue simulado del pipeline.

---

### Reflexiones EP3 (completar sin IA)

> Cada integrante escribe su reflexión con sus palabras, sin apoyo de IA (indicación de la evaluación). Aquí van el aprendizaje y el aporte concreto a la EP3.

#### Fabián Sánchez

**¿Qué aprendí en la EP3?**

_completar_

**¿Qué me costó?**

_completar_

**¿Cuál fue mi aporte?**

_completar_

#### Carlos Bastias

**¿Qué aprendí en la EP3?**

_completar_

**¿Qué me costó?**

_completar_

**¿Cuál fue mi aporte?**

_completar_
