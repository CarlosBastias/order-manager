# Fase 06 — Contenedores (Dockerfile)

## Objetivo
Empaquetar el microservicio en una imagen Docker que se pueda ejecutar igual en cualquier máquina o en la nube, sin tener que instalar Java ni Maven.

## Qué se hizo
Se creó un `Dockerfile` **multi-stage** en la raíz del proyecto:

```dockerfile
# Etapa 1: Construcción
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn clean package -DskipTests

# Etapa 2: Runtime
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
RUN groupadd --system appgroup && useradd --system --gid appgroup appuser
COPY --from=build /app/target/order-manager-1.0.0.jar app.jar
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8080
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

## Decisiones

| Decisión | Por qué |
|----------|---------|
| **Multi-stage** (build + runtime) | La etapa de build trae Maven y el JDK completo (pesado). La imagen final solo copia el `.jar` y usa el **JRE**, así queda mucho más liviana y con menos cosas que puedan tener vulnerabilidades. |
| Copiar primero `pom.xml` y correr `dependency:go-offline` | Docker cachea esa capa. Si solo cambia el código y no el `pom.xml`, no vuelve a descargar todas las dependencias, y el build es mucho más rápido. |
| `-DskipTests` dentro del Dockerfile | Las pruebas ya se corren en el pipeline antes de construir la imagen (job 1). Correrlas otra vez acá solo haría más lento el build. |
| Imagen base `eclipse-temurin:17-jre-jammy` | Imagen oficial de Java 17, mantenida y con actualizaciones de seguridad. Dependabot la revisa cada semana. |
| **Usuario no root** (`appuser`) | Si alguien llegara a explotar la app, no tendría permisos de root dentro del contenedor. |
| `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0` | La JVM lee el límite de memoria del contenedor y usa como máximo el 75% para el heap, dejando espacio para el resto del proceso. Evita que Docker mate el contenedor por memoria. |
| `.dockerignore` | No se copian al contexto de build `target/`, `.git`, `.github`, `docs`, etc. El build es más rápido y no se mete nada que no corresponda en la imagen. |

## Cómo probarlo

```bash
docker build -t order-manager:local .
docker image ls order-manager          # ver el tamaño
docker run --rm -p 8080:8080 order-manager:local
curl http://localhost:8080/actuator/health
```

## Relación con el pipeline
En el job **3. Imagen Docker** el pipeline construye esta misma imagen, le pone como tag el SHA del commit, le agrega labels OCI con el commit y el repo, y la escanea con **Snyk Container** antes de desplegarla.
