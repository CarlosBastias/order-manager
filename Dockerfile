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

# usuario sin privilegios con UID fijo (10001), así kubernetes puede verificar que no corre como root
RUN groupadd --system --gid 10001 appgroup && useradd --system --uid 10001 --gid appgroup appuser

COPY --from=build /app/target/order-manager-1.0.0.jar app.jar

RUN chown -R appuser:appgroup /app
USER 10001:10001

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]