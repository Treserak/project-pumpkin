#!/bin/sh
set -e

BACKUP_REPO="${BACKUP_REPO:-Treserak/project-pumpkin}"
GH_TOKEN="${GH_BACKUP_TOKEN}"
BACKUP_INTERVAL="${BACKUP_INTERVAL_SECONDS:-600}"
MAX_BACKUPS="${BACKUP_RETENTION_COUNT:-5}"
WORLD_DIR="/app/world"
FIFO_PATH="/tmp/pumpkin_stdin"
LAST_HASH_FILE="/app/last_hash.txt"

echo "=== [Project Pumpkin Supervisor Iniciado] ==="
echo "Repositorio de respaldos: $BACKUP_REPO"
echo "Intervalo de respaldo: ${BACKUP_INTERVAL}s"
echo "Retención FIFO: $MAX_BACKUPS copias"

# 1. Configurar directorios y descriptor FIFO para consola stdin
mkdir -p /app/world /app/www
rm -f "$FIFO_PATH"
mkfifo "$FIFO_PATH"
exec 3<> "$FIFO_PATH"

# 2. Función para calcular el hash determinista del mundo
compute_world_hash() {
  if [ ! -d "$WORLD_DIR" ] || [ -z "$(ls -A "$WORLD_DIR" 2>/dev/null)" ]; then
    echo "empty"
    return
  fi
  find "$WORLD_DIR" -type f \( -name "*.mca" -o -name "*.dat" -o -name "*.json" \) 2>/dev/null | sort | xargs -r sha256sum | sha256sum | awk '{print $1}'
}

# 3. Restaurar la copia más reciente desde GitHub Releases
restore_latest_world() {
  echo "[Supervisor:Restore] Comprobando respaldos existentes en GitHub..."
  if [ -z "$GH_TOKEN" ]; then
    echo "[Supervisor:Restore] ADVERTENCIA: GH_BACKUP_TOKEN no configurado. Omitiendo restauración."
    return
  fi

  RELEASES_JSON=$(curl -s -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$BACKUP_REPO/releases?per_page=1" || true)

  LATEST_TAG=$(echo "$RELEASES_JSON" | jq -r '.[0].tag_name // empty' 2>/dev/null || true)
  DOWNLOAD_URL=$(echo "$RELEASES_JSON" | jq -r '.[0].assets[] | select(.name=="world.tar.gz") | .browser_download_url' 2>/dev/null || true)

  if [ -n "$LATEST_TAG" ] && [ -n "$DOWNLOAD_URL" ]; then
    echo "[Supervisor:Restore] Encontrado respaldo reciente: $LATEST_TAG. Descargando..."
    curl -sL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/octet-stream" "$DOWNLOAD_URL" -o /tmp/world.tar.gz
    echo "[Supervisor:Restore] Extrayendo mundo..."
    tar -xzf /tmp/world.tar.gz -C /app
    rm -f /tmp/world.tar.gz
    INIT_HASH=$(compute_world_hash)
    echo "$INIT_HASH" > "$LAST_HASH_FILE"
    echo "$LATEST_TAG ($INIT_HASH)" > /app/last_backup.txt
    echo "[Supervisor:Restore] Restauración completada con éxito (Hash: $INIT_HASH)."
  else
    echo "[Supervisor:Restore] No se encontraron respaldos previos. Pumpkin generará un mundo nuevo."
    echo "initial" > "$LAST_HASH_FILE"
  fi
}

# 4. Función de respaldo diferencial con rotación FIFO (5 slots)
perform_backup() {
  if [ -z "$GH_TOKEN" ]; then
    echo "[Supervisor:Backup] GH_BACKUP_TOKEN ausente. Omitiendo respaldo."
    return
  fi

  echo "[Supervisor:Backup] Solicitando guardado en disco a Pumpkin..."
  echo "save-all" >&3
  sleep 3

  CURRENT_HASH=$(compute_world_hash)
  LAST_HASH=$(cat "$LAST_HASH_FILE" 2>/dev/null || echo "")

  if [ "$CURRENT_HASH" = "empty" ]; then
    echo "[Supervisor:Backup] El directorio del mundo aún está vacío. Omitiendo respaldo."
    return
  fi

  if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
    echo "[Supervisor:Backup] Ningún bloque modificado (Hash: ${CURRENT_HASH:0:12}). Respaldo omitido."
    return
  fi

  echo "[Supervisor:Backup] Cambios detectados (Hash actual: ${CURRENT_HASH:0:12} vs previo: ${LAST_HASH:0:12})."
  TAG_NAME="backup-$(date +%Y%m%d-%H%M%S)"
  
  echo "[Supervisor:Backup] Comprimiendo mundo a /tmp/world.tar.gz..."
  tar -czf /tmp/world.tar.gz -C /app world

  echo "[Supervisor:Backup] Creando release en GitHub: $TAG_NAME..."
  REL_RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$BACKUP_REPO/releases" \
    -d "{\"tag_name\":\"$TAG_NAME\",\"name\":\"Backup $TAG_NAME\",\"body\":\"Respaldo automático del mundo. SHA256: $CURRENT_HASH\",\"draft\":false,\"prerelease\":false}")

  REL_ID=$(echo "$REL_RESP" | jq -r '.id // empty' 2>/dev/null)
  
  if [ -z "$REL_ID" ]; then
    echo "[Supervisor:Backup] ERROR al crear release en GitHub. Respuesta: $REL_RESP"
    rm -f /tmp/world.tar.gz
    return
  fi

  echo "[Supervisor:Backup] Subiendo activo world.tar.gz a la release $REL_ID..."
  UPLOAD_RESP=$(curl -s -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Content-Type: application/gzip" \
    --data-binary @/tmp/world.tar.gz \
    "https://uploads.github.com/repos/$BACKUP_REPO/releases/$REL_ID/assets?name=world.tar.gz")

  rm -f /tmp/world.tar.gz
  echo "$CURRENT_HASH" > "$LAST_HASH_FILE"
  echo "$TAG_NAME (${CURRENT_HASH:0:12})" > /app/last_backup.txt
  echo "[Supervisor:Backup] Respaldo $TAG_NAME completado exitosamente."

  # Poda FIFO: Mantener exactamente MAX_BACKUPS
  echo "[Supervisor:FIFO] Verificando rotación de respaldos antiguos..."
  RELEASES_LIST=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$BACKUP_REPO/releases?per_page=30")

  TOTAL_COUNT=$(echo "$RELEASES_LIST" | jq '. | length' 2>/dev/null || echo 0)
  if [ "$TOTAL_COUNT" -gt "$MAX_BACKUPS" ]; then
    echo "[Supervisor:FIFO] Detectadas $TOTAL_COUNT releases (> $MAX_BACKUPS). Podando las más antiguas..."
    # Extraer las releases desde el índice MAX_BACKUPS en adelante (las más viejas)
    TO_PRUNE=$(echo "$RELEASES_LIST" | jq -r ".[$MAX_BACKUPS:] | .[] | \"\(.id) \(.tag_name)\"")
    while read -r pr_id pr_tag; do
      if [ -n "$pr_id" ]; then
        echo "[Supervisor:FIFO] Eliminando release obsoleta $pr_tag (ID: $pr_id)..."
        curl -s -X DELETE -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$BACKUP_REPO/releases/$pr_id" >/dev/null || true
        curl -s -X DELETE -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/repos/$BACKUP_REPO/git/refs/tags/$pr_tag" >/dev/null || true
      fi
    done <<EOF
$TO_PRUNE
EOF
    echo "[Supervisor:FIFO] Rotación completada. Total de respaldos en almacén: $MAX_BACKUPS."
  fi
}

# 5. Manejador de parada elegante (Graceful Shutdown)
shutdown_handler() {
  echo "[Supervisor] ¡Señal de terminación recibida! Iniciando apagado limpio..."
  perform_backup
  echo "stop" >&3
  sleep 2
  kill -TERM "$PUMPKIN_PID" 2>/dev/null || true
  kill -TERM "$PLAYIT_PID" 2>/dev/null || true
  kill -TERM "$UPDATER_PID" 2>/dev/null || true
  kill -TERM "$HTTPD_PID" 2>/dev/null || true
  wait "$PUMPKIN_PID" 2>/dev/null || true
  exec 3>&-
  echo "[Supervisor] Apagado limpio finalizado. Saliendo."
  exit 0
}

trap shutdown_handler SIGTERM SIGINT SIGHUP

# 6. Ejecutar restauración inicial
restore_latest_world

# 7. Iniciar Servidor HTTP Keep-Alive en puerto 7860
echo "[Supervisor] Iniciando micro-servidor HTTP en puerto 7860..."
busybox httpd -p 7860 -h /app/www
HTTPD_PID=$!
/app/http_updater.sh &
UPDATER_PID=$!

# 8. Iniciar Túnel Playit.gg
echo "[Supervisor] Iniciando túnel playitd..."
if [ -n "$PLAYIT_SECRET_KEY" ]; then
  playitd --platform-docker --secret "$PLAYIT_SECRET_KEY" -l /app/playit.log >/dev/null 2>&1 &
else
  playitd --platform-docker -l /app/playit.log >/dev/null 2>&1 &
fi
PLAYIT_PID=$!

# 9. Iniciar Servidor Minecraft Pumpkin
echo "[Supervisor] Iniciando motor Pumpkin..."
/usr/local/bin/pumpkin <&3 2>&1 | tee -a /app/pumpkin.log &
PUMPKIN_PID=$!

echo "[Supervisor] Todos los servicios han arrancado correctamente. Entrando en bucle de respaldo."

# 10. Bucle de respaldo cada 10 minutos (en pasos de 5s para respuesta ágil a señales)
TICKS=0
while kill -0 "$PUMPKIN_PID" 2>/dev/null; do
  sleep 5
  TICKS=$((TICKS + 5))
  if [ "$TICKS" -ge "$BACKUP_INTERVAL" ]; then
    perform_backup
    TICKS=0
  fi
done

echo "[Supervisor] El proceso de Pumpkin terminó inesperadamente. Ejecutando parada de emergencia."
shutdown_handler
