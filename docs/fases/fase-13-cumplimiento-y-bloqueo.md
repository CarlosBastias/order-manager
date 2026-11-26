# Fase 13 — Cumplimiento y bloqueo del pipeline (EP3: IE5 e IE6)

## Políticas aplicadas
| Política | Herramienta | Dónde | Efecto |
|----------|-------------|-------|--------|
| Quality Gate (bugs, vulnerabilidades, duplicación, cobertura del código nuevo) | SonarCloud | job 2 | falla el job → no se construye la imagen |
| Vulnerabilidades altas/críticas en dependencias | Snyk (+ `.snyk` con excepciones que vencen) | job 2 | falla el job |
| Dependencias nuevas vulnerables en un PR | Dependency Review | job 2b | PR en rojo |
| Cobertura mínima 60 % y pruebas | JaCoCo + JUnit | job 1 | falla el job |
| Auditoría propia (`scripts/audit.py`) | script Python | job 2c | si hay un ERROR no se construye la imagen |
| Vulnerabilidades críticas en la imagen | Snyk Container | job 3 | no se despliega |
| PR obligatorio + checks en verde + 1 aprobación | Branch protection | GitHub (`scripts/branch-protection.sh`) | no se puede mergear a `main` |

## Reglas de `scripts/audit.py`
| Área | Regla | Nivel |
|------|-------|-------|
| Secretos | sin llaves privadas, access keys de AWS, tokens de GitHub/Slack ni `password/secret/token/api_key` con valor escrito; sin `.env` versionado | ERROR |
| Dockerfile | imagen final sin root; imágenes base con versión fija; sin secretos en `ENV/ARG` | ERROR |
| Kubernetes | requests y limits de CPU y memoria, liveness y readiness, imagen con versión fija; imagen propia sin root y sin escalada de privilegios (de terceros: advertencia) | ERROR / ADVERTENCIA |
| Docker Compose | límite de memoria en cada servicio; base de datos no expuesta hacia afuera; `docker.sock` solo en `:ro` (advertencia) o con escritura (error) | ERROR / ADVERTENCIA |
| Pipeline | `permissions` declarado y acciones sin `@main/@master/@latest` | ERROR |

Las ERROR hacen `exit 1` y detienen el pipeline; las ADVERTENCIA solo se informan. El reporte queda en el *Summary* del run y como artefacto `audit-report`.

## Activar la protección de rama
```bash
gh auth login
bash scripts/branch-protection.sh
```
(En un repositorio privado con plan gratis GitHub no permite protección de ramas: el repo debe ser público.)

## Demostración 1 — la auditoría detiene el pipeline (un clic)
```bash
gh workflow run ci-cd.yml --ref dev -f simular_falla=true
gh run watch
```
Lo mismo desde la web: *Actions → CI/CD order-manager → Run workflow → simular_falla ✔*.

Qué pasa: el job `2c` agrega un archivo con `db.password=admin123` (solo en el runner), `audit.py` lo marca como ERROR, el job falla, y los jobs `3`, `4`, `4b` quedan **saltados** (no se construye ni despliega nada). Resultado esperado de la auditoría:

```
Resultado: ❌ FALLA (1 errores, ...)
| Secretos | ❌ ERROR | src/main/resources/demo-falla.properties:1 | 'db.password' tiene un valor escrito en el código; debe venir de una variable de entorno o secret |
```
(Probado en local: sin la falla el script termina con código 0 y con la falla con código 1.)

## Demostración 2 — un PR con una prueba rota no se puede mergear
```bash
git checkout -b demo/prueba-falla dev
# romper una prueba a propósito, por ejemplo cambiar un assertEquals en OrderServiceTest
git commit -am "demo: prueba rota para mostrar el bloqueo" && git push -u origin demo/prueba-falla
gh pr create --base dev --title "DEMO bloqueo" --body "Prueba rota a propósito"
```
El job 1 falla, todo lo demás queda saltado y el PR muestra los checks en rojo. Saquen captura y **cierren el PR sin mergear** (`gh pr close --delete-branch`).

## Demostración 3 (opcional) — Snyk bloquea una dependencia vulnerable
En una rama aparte, bajar una dependencia a una versión con vulnerabilidad alta conocida; Snyk (job 2) y Dependency Review (2b) fallan. Esto ya ocurrió de verdad en la EP2 (Spring Boot 3.3.4) y está documentado en el README.

Guarden las capturas en `docs/evidencias/` (ver la lista de ese directorio).
