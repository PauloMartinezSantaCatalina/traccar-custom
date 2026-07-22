# ============================================================
# TRACCAR GPS - DOCKERFILE MULTI-STAGE
# Compila desde código fuente para Render Free Tier
# ============================================================

# ============================================================
# STAGE 1: Build Backend (Java + Gradle)
# ============================================================
FROM eclipse-temurin:21-jdk AS backend-builder

WORKDIR /build

# Copiar archivos de build primero (mejora cache de capas)
COPY build.gradle settings.gradle gradlew ./
COPY gradle/ ./gradle/

# Copiar código fuente del backend
COPY src/ ./src/
COPY schema/ ./schema/

# Dar permisos y compilar (sin tests para velocidad)
RUN chmod +x gradlew && ./gradlew assemble --no-daemon -x test

# ============================================================
# STAGE 2: Build Frontend (Node.js + Vite)
# ============================================================
FROM node:22-slim AS frontend-builder

WORKDIR /build

# Copiar package.json y package-lock.json primero (mejora cache)
COPY traccar-web/package.json traccar-web/package-lock.json ./

# Instalar dependencias
RUN npm install

# Copiar código fuente del frontend
COPY traccar-web/src/ ./src/
COPY traccar-web/public/ ./public/
COPY traccar-web/index.html ./
COPY traccar-web/vite.config.js ./

# Compilar frontend
RUN npm run build

# ============================================================
# STAGE 3: Runtime Final (JRE ligero)
# ============================================================
FROM eclipse-temurin:21-jre-alpine

# Instalar dependencias del sistema
RUN apk add --no-cache bash tzdata curl

# Crear directorios de trabajo
WORKDIR /opt/traccar

# Copiar backend compilado desde Stage 1
COPY --from=backend-builder /build/target/tracker-server.jar ./
COPY --from=backend-builder /build/target/lib/ ./lib/

# Copiar frontend compilado desde Stage 2
COPY --from=frontend-builder /build/build/ ./web/

# Copiar archivos de configuración y esquemas
COPY schema/ ./schema/
COPY templates/ ./templates/

# Copiar traducciones del frontend
COPY traccar-web/src/resources/l10n/ ./web/l10n/

# ============================================================
# CONFIGURACIÓN PARA RENDER FREE TIER
# ============================================================

# Crear directorio de configuración
RUN mkdir -p /opt/traccar/conf

# Copiar traccar.xml precreado (evita problemas de encoding con echo/cat)
COPY conf/traccar.xml /opt/traccar/conf/traccar.xml

# Crear directorios necesarios
RUN mkdir -p /opt/traccar/data /opt/traccar/logs

# Puerto de Traccar
EXPOSE 8082

# Comando de inicio
ENTRYPOINT ["java", "-XX:+ExitOnOutOfMemoryError", "-jar", "tracker-server.jar", "conf/traccar.xml"]
