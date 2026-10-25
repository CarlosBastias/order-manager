# Fase 09 — Pipeline CI/CD (GitHub Actions)

## Objetivo
Automatizar todo el ciclo: cada cambio que se sube se compila, se prueba, se analiza (calidad y seguridad), se empaqueta en una imagen y se despliega en un entorno simulado. Si algo falla, el pipeline se detiene y avisa.

Archivo: `.github/workflows/ci-cd.yml`

## Disparadores
- `push` a `main` y `dev`
- `pull_request` hacia `main` y `dev` (las ramas `feature/*` se validan por su PR, así no corre dos veces lo mismo)
- `workflow_dispatch` (ejecución manual desde la pestaña Actions)

Además tiene `concurrency`: si se hace otro push a la misma rama, se cancela la ejecución anterior.

## Etapas

| # | Job | Qué hace | Bloquea si... |
|---|-----|----------|---------------|
| 1 | `build-test` | checkout, Java 17 (Temurin) con caché Maven, `mvn -B clean verify` (pruebas + JaCoCo), revisa cobertura mínima, sube reportes y `.jar` | falla una prueba o la cobertura es < 60% |
| 2 | `security-scan` | Snyk CLI: `snyk test --severity-threshold=high` (respeta las excepciones de `.snyk`), reporte JSON como artefacto, `snyk monitor` en main | hay vulnerabilidades high o critical en dependencias |
| 2 | `code-analysis` | SonarCloud con `sonar-project.properties`, usando las clases y reportes del job 1. Corre en PR y en `main` | no pasa el **Quality Gate** |
| 2b | `dependency-review` | solo en PR: revisa las dependencias nuevas | se agrega una dependencia con vulnerabilidad high |
| 3 | `docker-build` | build de la imagen con Buildx, tags `<sha>` y `latest`, labels OCI, Snyk Container, exporta la imagen | hay vulnerabilidades críticas en la imagen |
| 4 | `deploy` | carga la imagen, `docker compose up --wait`, smoke test, resumen del despliegue | la app no queda healthy o falla el smoke test |
| 5 | `notify-failure` | si algo falló en un push a `main`/`dev`: error visible en el run, tabla en el Summary e issue automático | — |

Los jobs 2 (Snyk y Sonar) corren **en paralelo** porque no dependen uno del otro; el job 3 espera a que **los dos** pasen.

## Bloqueos (gates)
1. **Pruebas**: `mvn clean verify` devuelve error si una prueba falla → el job 1 falla → no corre nada más.
2. **Cobertura**: se lee `target/site/jacoco/jacoco.csv` y se calcula el % de líneas cubiertas. Bajo `MIN_COVERAGE` el job falla.
3. **Quality Gate**: `sonar.qualitygate.wait=true` hace que el scanner espere la respuesta de SonarCloud y falle si el gate queda en rojo. El plan gratis de SonarCloud solo analiza `main` y los Pull Requests, así que en un push a `dev` el escaneo se salta con un aviso: ese código ya pasó el Quality Gate en su PR.
4. **Snyk dependencias**: `--severity-threshold=high`. Las únicas excepciones están en el archivo `.snyk`, cada una con motivo y fecha de vencimiento (ver más abajo).
5. **Snyk imagen**: `--severity-threshold=critical`, solo vulnerabilidades del sistema base (las de la app ya las revisa el job 2).
6. **Despliegue**: `--wait` + smoke test.
7. **Merge**: con la protección de rama en `main` (status checks obligatorios) un PR con el pipeline en rojo no se puede mergear.

## Excepciones de seguridad (`.snyk`)
Cuando una vulnerabilidad no tiene parche y no aplica al proyecto, se acepta de forma documentada en `.snyk` con su ID exacto, el motivo y una fecha de vencimiento. Al vencer, Snyk vuelve a bloquear y hay que revisarla.

Hoy hay una sola: `SNYK-JAVA-ORGGLASSFISHJAXB-20883142` (XXE en `jaxb-core`, que viene dentro de Hibernate). No existe versión corregida y la API no procesa XML, solo JSON. Vence el 31-01-2027.

**Historial del bloqueo**: Snyk detuvo el pipeline con Spring Boot 3.3.4. Se subió a 3.5.16 y seguía con 26 vulnerabilidades (esa rama ya no tiene parches gratuitos), así que se migró a Spring Boot 4.0.8 (13 vulnerabilidades) y luego a 4.0.9, que dejó solo la de `jaxb-core`.

## Alertas
- Job 5 en cada falla de un push a `main` o `dev`: marca el run con un error visible, deja en el Summary una tabla con el resultado de cada job y abre un issue automático (si los Issues estuvieran desactivados, deja un aviso y no se cae).
- `snyk monitor` en main: Snyk manda correo cuando aparece una vulnerabilidad nueva en las dependencias, aunque no se haya hecho push.
- Dependabot: alertas de seguridad en la pestaña *Security* y PR automáticos de actualización cada lunes.
- GitHub además manda correo al autor del commit cuando su run falla.

## Seguridad dentro del pipeline
- `permissions: contents: read` a nivel global; solo `dependency-review` pide `pull-requests: write` y `notify-failure` pide `issues: write`.
- Tokens (`SONAR_TOKEN`, `SNYK_TOKEN`) y la clave de la base (`POSTGRES_PASSWORD`) como **GitHub Secrets**. La clave generada al azar se oculta con `::add-mask::`.
- `timeout-minutes` en cada job para que nada quede colgado gastando minutos.

## Trazabilidad
- Imagen con tag = SHA del commit y labels `org.opencontainers.image.revision` / `source` / `version`.
- La imagen que se despliega es la misma que se construyó y escaneó (pasa como artefacto entre jobs).
- Environment `simulated-production`: historial de despliegues en GitHub.
- Resumen del despliegue en la pestaña *Summary* (commit, rama, autor, imagen, run).
- Artefactos por run: `reportes-pruebas`, `app-jar`, `snyk-report`, `docker-image`.
- Excepciones de seguridad versionadas en `.snyk` (quién, cuándo y por qué queda en el historial de git).

## Dependabot (`.github/dependabot.yml`)
Revisa **todos los lunes a las 08:00 (hora de Chile)**:
- `maven` → dependencias del `pom.xml` (las de Spring agrupadas en un solo PR)
- `github-actions` → versiones de las actions del workflow
- `docker` → imágenes base del `Dockerfile`

Cada actualización llega como PR y pasa por el mismo pipeline antes de poder mergearse.

## Configuración previa
Ver la sección *Configuración necesaria en GitHub* del README (SonarCloud, Snyk, secrets y protección de rama).