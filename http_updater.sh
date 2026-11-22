#!/bin/sh
# Micro-daemon that updates the web dashboard index.html for busybox httpd on port 7860
WWW_DIR="/app/www"
mkdir -p "$WWW_DIR"

while true; do
  UPTIME_STR=$(uptime -p 2>/dev/null || uptime)
  MEM_USAGE=$(free -m | awk '/Mem:/ {print $3 "MB / " $2 "MB"}')
  
  PLAYIT_STATUS="Inicializando..."
  if [ -f "/app/playit.log" ]; then
    CLAIM_URL=$(grep -oE 'https://playit\.gg/claim/[a-zA-Z0-9]+' /app/playit.log | tail -n 1)
    if [ -n "$CLAIM_URL" ]; then
      PLAYIT_STATUS="<span style='color:#f59e0b; font-weight:bold;'>⚠️ Reclama tu túnel:</span> <a href='$CLAIM_URL' target='_blank' style='color:#38bdf8; font-weight:bold; text-decoration: underline;'>$CLAIM_URL</a>"
    elif pgrep -x playitd >/dev/null 2>&1; then
      PLAYIT_STATUS="<span style='color:#22c55e;'>Túnel activo y conectado</span>"
    else
      PLAYIT_STATUS="<span style='color:#ef4444;'>Túnel no iniciado</span>"
    fi
  fi

  LAST_BACKUP="Ninguno registrado todavía"
  if [ -f "/app/last_backup.txt" ]; then
    LAST_BACKUP=$(cat /app/last_backup.txt)
  fi

  PUMPKIN_STATE="<span style='color:#ef4444;'>Detenido</span>"
  if pgrep -x pumpkin >/dev/null 2>&1; then
    PUMPKIN_STATE="<span style='color:#22c55e;'>En línea (Activo)</span>"
  fi

  cat <<EOF > "$WWW_DIR/index.html.tmp"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Project Pumpkin - Estado</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; display: flex; justify-content: center; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 12px; padding: 2rem; max-width: 650px; width: 100%; box-shadow: 0 10px 25px -5px rgba(0,0,0,0.5); }
    h1 { color: #f97316; margin-top: 0; display: flex; align-items: center; gap: 0.5rem; font-size: 1.6rem; }
    .badge { background: #0369a1; color: #e0f2fe; padding: 0.2rem 0.6rem; border-radius: 9999px; font-size: 0.8rem; font-weight: bold; }
    .metric { margin: 1rem 0; border-bottom: 1px solid #334155; padding-bottom: 0.75rem; }
    .metric-title { font-weight: bold; color: #94a3b8; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; }
    .metric-value { font-size: 1.1rem; margin-top: 0.25rem; word-break: break-all; }
    .footer { margin-top: 1.5rem; font-size: 0.8rem; color: #64748b; text-align: center; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🎃 Project Pumpkin <span class="badge">Rust Native</span></h1>
    <p style="color: #94a3b8; margin-top:-0.5rem; font-size: 0.9rem;">Servidor Minecraft optimizado con musl sobre Alpine Linux</p>
    
    <div class="metric">
      <div class="metric-title">Estado del Servidor</div>
      <div class="metric-value">$PUMPKIN_STATE</div>
    </div>

    <div class="metric">
      <div class="metric-title">Conectividad Túnel Playit.gg</div>
      <div class="metric-value">$PLAYIT_STATUS</div>
    </div>

    <div class="metric">
      <div class="metric-title">Último Respaldo a GitHub</div>
      <div class="metric-value">$LAST_BACKUP</div>
    </div>

    <div class="metric">
      <div class="metric-title">Consumo de Memoria RAM</div>
      <div class="metric-value">$MEM_USAGE</div>
    </div>

    <div class="metric">
      <div class="metric-title">Tiempo de Actividad</div>
      <div class="metric-value">$UPTIME_STR</div>
    </div>

    <div class="footer">
      Actualizado automáticamente en tiempo real | Puerto 7860 Keep-Alive
    </div>
  </div>
</body>
</html>
EOF
  mv "$WWW_DIR/index.html.tmp" "$WWW_DIR/index.html"
  sleep 5
done
