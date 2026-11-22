FROM docker.io/library/alpine:3.21

# Instalar dependencias esenciales de sistema (cero bloat, estrictamente mínimas)
RUN apk add --no-cache \
    curl \
    jq \
    tar \
    ca-certificates \
    tini \
    procps \
    busybox-extras

# Instalar binario de Pumpkin compilado estáticamente con musl (x86_64)
RUN curl -sSL https://github.com/SrDicov/Pumpkin/releases/download/v0.2.2-musl/pumpkin-X64-Linux -o /usr/local/bin/pumpkin && \
    chmod +x /usr/local/bin/pumpkin

# Instalar binarios de Playit.gg (daemon y CLI estáticos)
RUN curl -sSL https://github.com/playit-cloud/playit-agent/releases/download/v2.0.2/playit-linux-amd64 -o /usr/local/bin/playitd && \
    curl -sSL https://github.com/playit-cloud/playit-agent/releases/download/v2.0.2/playit-cli-linux-amd64 -o /usr/local/bin/playit && \
    chmod +x /usr/local/bin/playitd /usr/local/bin/playit

# Crear usuario sin privilegios requerido por Hugging Face Spaces (UID 1000)
RUN adduser -u 1000 -D -h /app app

WORKDIR /app

# Copiar configuraciones y scripts supervisores
COPY pumpkin.toml /app/pumpkin.toml
COPY entrypoint.sh /app/entrypoint.sh
COPY http_updater.sh /app/http_updater.sh

# Asegurar permisos correctos en todo el árbol de la aplicación
RUN mkdir -p /app/world /app/www && \
    chmod +x /app/entrypoint.sh /app/http_updater.sh && \
    chown -R app:app /app

USER app

EXPOSE 7860 25565 19132

ENTRYPOINT ["/sbin/tini", "--", "/app/entrypoint.sh"]
