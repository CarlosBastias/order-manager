# Fase 10 — Documentación

## Objetivo
Dejar el proyecto documentado para que cualquier persona (o el equipo en el futuro) pueda entender qué hace, levantarlo y saber cómo funciona el pipeline sin tener que preguntar.

## Qué se documentó

| Documento | Contenido |
|-----------|-----------|
| `README.md` | Integrantes, tecnologías, endpoints, cómo ejecutar en local y con Docker, pipeline por etapas, bloqueos y alertas, trazabilidad, calidad, orquestación, configuración de GitHub, estructura, uso de IA y reflexiones individuales |
| `docs/fases/fase-06-contenedores.md` | Dockerfile multi-stage y por qué se tomó cada decisión |
| `docs/fases/fase-07-perfil-docker.md` | Perfiles de Spring (H2 vs PostgreSQL) y manejo de la clave |
| `docs/fases/fase-08-orquestacion.md` | Docker Compose: servicios, healthchecks, dependencias y recursos |
| `docs/fases/fase-09-cicd.md` | Pipeline de GitHub Actions, gates, alertas, seguridad y Dependabot |
| `sonar-project.properties` | Comentado con qué hace cada propiedad |
| `.github/workflows/ci-cd.yml` | Comentado por etapa y por paso |
| `.github/dependabot.yml` | Comentado por ecosistema |

## Criterios que seguimos
- El README es la **entrada principal**: lo primero que se ve en el repo tiene que explicar cómo correrlo.
- Los comandos están listos para copiar y pegar.
- Cada decisión técnica tiene su **por qué**, no solo el qué.
- Los archivos de configuración tienen comentarios en el mismo archivo, para no tener que ir a otro lado a buscar qué hace cada línea.
- La documentación está en el mismo repositorio que el código, así se versiona junto con los cambios (si cambia el pipeline, en el mismo PR se actualiza su documentación).

## Uso de IA
Se declara en la sección **Uso de IA** del README: qué herramienta se usó, para qué y cómo se validó, con la cita correspondiente según [bibliotecas.duoc.cl/ia](https://bibliotecas.duoc.cl/ia). Las reflexiones individuales se escribieron sin IA.

## Checklist de entrega
- [ ] Reemplazar `USUARIO/REPO` en el badge y en el `git clone` del README
- [ ] Poner nombre y usuario del compañero en *Integrantes* y en *Reflexiones*
- [ ] Reemplazar `sonar.projectKey` y `sonar.organization` en `sonar-project.properties`
- [ ] Crear secrets `SONAR_TOKEN` y `SNYK_TOKEN`
- [ ] Desactivar *Automatic Analysis* en SonarCloud
- [ ] Activar Dependabot alerts y protección de rama en `main`
- [ ] Verificar que el último run del pipeline en `main` esté en verde
- [ ] Escribir las reflexiones individuales (sin IA)
- [ ] Subir el link del repo a AVA y mandarlo por correo al docente
