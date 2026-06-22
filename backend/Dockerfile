# Multi-stage build for the Grocery-Mart Spring Boot API (Java 21 / Spring Boot 4.1).
# Build:  docker build -t grocery-mart-api ./backend
# Run:    docker run -p 8080:8080 -e DB_URL=... -e POSTGRES_USER=... -e POSTGRES_PASSWORD=... grocery-mart-api
# On Render this is built automatically from render.yaml (dockerfilePath: ./backend/Dockerfile).

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
# Cache dependencies first
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline -B || true
# Build the fat jar
COPY src ./src
RUN mvn -q -DskipTests -B package \
 && cp target/api-0.0.1-SNAPSHOT.jar app.jar

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/app.jar app.jar
# Render/most PaaS inject a $PORT; default to 8080 for local runs.
ENV PORT=8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75"
EXPOSE 8080
# Spring binds to ${PORT}; all other config (DB_URL, POSTGRES_*, JWT_SECRET, GROCERYMART_CORS_ORIGINS)
# is supplied as environment variables at runtime.
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -Dserver.port=${PORT} -jar app.jar"]
