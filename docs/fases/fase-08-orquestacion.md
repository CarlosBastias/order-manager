# Fase 08 — Orquestación con Docker Compose

## Objetivo
Levantar la aplicación completa (API + base de datos) con un solo comando, con el orden de arranque correcto, recursos limitados y recuperación automática. Este mismo archivo se usa después en el despliegue simulado del pipeline.

## Servicios

```
           red: order-net (bridge)
┌───────────────────────┐      ┌──────────────────────┐
│ app                   │ ───► │ db                   │
│ order-manager:<tag>   │ JDBC │ postgres:16          │
│ :8080                 │      │ :5432 (solo 127.0.0.1)│
│ healthcheck /actuator │      │ healthcheck pg_isready│
└───────────────────────┘      └──────────┬───────────┘
                                          │
                                   volumen pg_data
```

| Servicio | Config clave |
|----------|--------------|
| `db` | `postgres:16`, volumen `pg_data`, healthcheck `pg_isready`, clave desde `${POSTGRES_PASSWORD}`, puerto expuesto solo en `127.0.0.1`, límite 1 CPU / 512 MB |
| `app` | imagen `order-manager:${IMAGE_TAG:-local}` + `build` del Dockerfile, perfil `docker`, `depends_on` con `condition: service_healthy`, healthcheck al actuator, límite 1 CPU / 768 MB y reserva de 256 MB |

## Decisiones

| Decisión | Por qué |
|----------|---------|
| `depends_on` con `condition: service_healthy` | `depends_on` normal solo espera a que el contenedor de la db **exista**, no a que PostgreSQL acepte conexiones. Con la condición `service_healthy` la app parte solo cuando `pg_isready` responde OK, así no se cae al inicio por no poder conectarse. |
| Healthcheck en la app | La imagen JRE no trae `curl`, por eso el healthcheck abre una conexión con `/dev/tcp` de bash y revisa que `/actuator/health` responda `UP`. Tiene `start_period: 60s` porque Spring Boot se demora en levantar. |
| Límites de CPU y memoria (`deploy.resources`) | Ningún contenedor puede usar toda la máquina. Junto con `MaxRAMPercentage=75.0` la JVM se ajusta sola al límite. |
| `restart: unless-stopped` | Si un contenedor se cae, Docker lo vuelve a levantar solo (a menos que lo bajemos a mano). |
| Volumen `pg_data` | Los pedidos no se pierden al reiniciar los contenedores. |
| Red propia `order-net` | Los servicios se comunican por nombre (`db`) y quedan aislados de otros contenedores. |
| Puerto de la db en `127.0.0.1` | Se puede revisar la base desde la propia máquina, pero no queda abierta hacia la red. |
| `image` + `build` en la app | En local `docker compose up --build` construye la imagen como `order-manager:local`. En el pipeline se usa `--no-build` con `IMAGE_TAG=<sha>`, así se despliega la misma imagen que ya pasó las pruebas y el escaneo. |
| Clave por variable de entorno | En local se usa la de desarrollo o la del `.env`; en el pipeline viene de un secret o se genera al azar. |

## Comandos

```bash
docker compose up -d --build     # construir y levantar
docker compose ps                # estado (deberían salir los dos "healthy")
docker compose logs -f app       # logs de la app
docker stats                     # ver consumo vs límites
docker compose restart app       # reiniciar solo la app
docker compose down              # bajar (se mantienen los datos)
docker compose down -v           # bajar y borrar el volumen
```

## En el pipeline
El job **4. Despliegue simulado** ejecuta:

```bash
docker compose up -d --no-build --wait --wait-timeout 180
```

`--wait` hace que el comando no termine hasta que los healthchecks de `db` y `app` estén OK; si no lo logran, el job falla. Después se corre el smoke test y al final `docker compose down -v`.
