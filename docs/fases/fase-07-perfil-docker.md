# Fase 07 — Perfil Docker (configuración por entorno)

## Objetivo
Que la misma aplicación funcione en local con una base en memoria y en Docker con PostgreSQL, **sin cambiar código**, solo cambiando el perfil de Spring.

## Perfiles

| | Por defecto (`application.properties`) | `docker` (`application-docker.properties`) |
|---|---|---|
| Uso | Desarrollo local y pruebas | Contenedor / despliegue simulado |
| Base de datos | H2 en memoria (`jdbc:h2:mem:orderdb`) | PostgreSQL 16 (`jdbc:postgresql://db:5432/orderdb`) |
| `ddl-auto` | `create-drop` (se borra al apagar) | `update` (los datos se mantienen) |
| SQL en consola | `show-sql=true` | `show-sql=false` |
| Consola H2 | Activada en `/h2-console` | No aplica |
| Puerto | 8098 | 8080 |
| Actuator | `health` e `info` | `health` e `info` |

## Cómo se activa
En el `docker-compose.yml` se le pasa la variable de entorno al contenedor de la app:

```yaml
environment:
  SPRING_PROFILES_ACTIVE: docker
```

Spring carga primero `application.properties` y después pisa los valores con los de `application-docker.properties`.

## Detalles importantes
- **`db` como host**: en la URL de conexión se usa `db` y no `localhost`, porque dentro de la red de Docker Compose cada servicio se encuentra por su nombre.
- **Clave de la base fuera del código**: aunque el properties tiene una clave de desarrollo, en compose se define `SPRING_DATASOURCE_PASSWORD: ${POSTGRES_PASSWORD:-orderpass}`. Spring le da prioridad a las variables de entorno sobre el archivo, así que en el pipeline la clave real viene de un secret de GitHub (o se genera al azar) y nunca queda escrita en el repo.
- **`open-in-view=false`**: evita que la sesión de JPA quede abierta durante toda la request, que es una mala práctica y Spring lo advierte en los logs.
- **Actuator `/actuator/health`**: con `show-details=always` muestra también el estado de la conexión a la base. Lo usa el healthcheck del contenedor y el smoke test del pipeline.
- **Pruebas**: las pruebas no usan el perfil docker; corren con el perfil por defecto (H2) o con mocks, así el pipeline no necesita levantar PostgreSQL para probar.

## Cómo probarlo

```bash
# perfil por defecto
mvn spring-boot:run
curl http://localhost:8098/actuator/health

# perfil docker
docker compose up -d --build
curl http://localhost:8080/actuator/health    # debería mostrar "db": {"status": "UP"}
```
