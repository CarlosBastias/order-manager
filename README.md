# Order Manager API — Pipeline CI/CD

![CI/CD](https://github.com/CarlosBastias/order-manager/actions/workflows/ci-cd.yml/badge.svg)

Microservicio REST para gestionar pedidos de un e-commerce (crear pedidos, agregar ítems y moverlos por sus estados). Está hecho en **Spring Boot 4.0 + Java 17**, se empaqueta en un contenedor Docker y se despliega de forma automática con un pipeline de **GitHub Actions**.

Evaluación Parcial 2 — DOY0101 Ingeniería DevOps — Duoc UC.

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
10. [Configuración necesaria en GitHub](#configuración-necesaria-en-github)
11. [Estructura del proyecto](#estructura-del-proyecto)
12. [Uso de IA](#uso-de-ia)
13. [Reflexiones individuales](#reflexiones-individuales)

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
          ┌───────────────────┼────────────────────┐
          ▼                   ▼                    ▼
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────────┐
│ 2. Snyk (SCA)    │ │ 2. SonarCloud    │ │ 2b. Dependency Review│ (solo en PR)
│ deps high/crit   │ │ Quality Gate     │ │ deps high            │
└────────┬─────────┘ └────────┬─────────┘ └──────────────────────┘
         └──────────┬─────────┘
                    ▼
       ┌──────────────────────────┐
       │ 3. Imagen Docker         │  build + labels OCI + Snyk Container
       └────────────┬─────────────┘
                    ▼
       ┌──────────────────────────┐
       │ 4. Despliegue simulado   │  docker compose up --wait + smoke test
       └────────────┬─────────────┘
                    ▼ (solo si algo falló en un push)
       ┌──────────────────────────┐
       │ 5. Alerta                │  abre un issue automático
       └──────────────────────────┘
```

### 1. Build y pruebas (`build-test`)
- `actions/checkout` con historial completo (Sonar lo necesita para saber qué código es nuevo).
- `actions/setup-java` con **Temurin 17** y caché de Maven para que no descargue todo cada vez.
- `mvn -B clean verify`: compila, corre las **24 pruebas** (16 de `OrderServiceTest` y 8 de `OrderControllerTest`) y genera el reporte de JaCoCo. **Si una prueba falla, Maven termina con error y el pipeline se detiene ahí.**
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

- **Pruebas automatizadas**: 24 pruebas (JUnit 5 + Mockito + MockMvc) que cubren lo crítico del negocio: crear pedidos, agregar ítems, las transiciones de estado válidas, las inválidas (por ejemplo cancelar un pedido ya entregado o ya cancelado, o agregar ítems a un pedido que no está PENDING) y los códigos HTTP (200, 201, 204, 400, 404, 409).
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
   - *Require status checks to pass* → marcar `1. Build y pruebas (JUnit + JaCoCo)`, `2. Seguridad de dependencias (Snyk)`, `2. Calidad de código (SonarCloud)` y `3. Imagen Docker + escaneo de seguridad`.

---

## Estructura del proyecto

```
.
├── .github/
│   ├── dependabot.yml           # actualizaciones semanales (maven, actions, docker)
│   └── workflows/ci-cd.yml      # pipeline CI/CD
├── docs/fases/                  # documentación de cada fase del proyecto
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

Documentación por fase: [Fase 06 – Contenedores](docs/fases/fase-06-contenedores.md) · [Fase 07 – Perfil Docker](docs/fases/fase-07-perfil-docker.md) · [Fase 08 – Orquestación](docs/fases/fase-08-orquestacion.md) · [Fase 09 – CI/CD](docs/fases/fase-09-cicd.md) · [Fase 10 – Documentación](docs/fases/fase-10-documentacion.md)

---

## Uso de IA

Declaración según las indicaciones de la evaluación ([bibliotecas.duoc.cl/ia](https://bibliotecas.duoc.cl/ia)):

| Herramienta | Para qué se usó | Cómo lo validamos |
|-------------|-----------------|-------------------|
| Claude (Anthropic) | Apoyo para armar la estructura del workflow de GitHub Actions, la configuración de Dependabot, SonarCloud y Snyk, interpretar los reportes de Snyk y hacer la migración a Spring Boot 4, y para ordenar y redactar este README y los documentos de fases 06 a 10 | Revisamos cada archivo, lo comparamos con el material del curso, probamos el pipeline en GitHub Actions y ajustamos lo que no calzaba con nuestro proyecto |

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
