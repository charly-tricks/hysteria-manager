#!/bin/bash
# ============================================================
#   HYSTERIA MANAGER - by CHARLY_TRICKS
#   Versión 1.0
#   Soporte: Hysteria V1 y V2
# ============================================================

# ── Colores ──────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ── Rutas ────────────────────────────────────────────────────
CONFIG_DIR="/etc/hysteria"
DB_V1="$CONFIG_DIR/users_v1.db"
DB_V2="$CONFIG_DIR/users_v2.db"
CONFIG_V1="$CONFIG_DIR/config_v1.json"
CONFIG_V2="$CONFIG_DIR/config_v2.yaml"
LOG_FILE="/var/log/hysteria_manager.log"
BACKUP_DIR="/root/hysteria_backups"
TG_CONFIG="$CONFIG_DIR/telegram.conf"
BIN_V1="/usr/local/bin/hysteria-v1"
BIN_V2="/usr/local/bin/hysteria-v2"
MANAGER_PATH="/usr/local/bin/hysteria"

# ── Verificar root ───────────────────────────────────────────
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}Error: Este script debe ejecutarse como root.${NC}"
    exit 1
fi

# ── Logger ───────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ── Notificación Telegram ────────────────────────────────────
send_telegram() {
    local mensaje="$1"
    if [ -f "$TG_CONFIG" ]; then
        source "$TG_CONFIG"
        if [ -n "$TG_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
            curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
                -d "chat_id=$TG_CHAT_ID" \
                -d "text=$mensaje" \
                -d "parse_mode=HTML" > /dev/null 2>&1
        fi
    fi
}

# ── Banner ───────────────────────────────────────────────────
mostrar_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ██████╗██╗  ██╗ █████╗ ██████╗ ██╗  ██╗   ██╗"
    echo " ██╔════╝██║  ██║██╔══██╗██╔══██╗██║  ╚██╗ ██╔╝"
    echo " ██║     ███████║███████║██████╔╝██║   ╚████╔╝ "
    echo " ██║     ██╔══██║██╔══██║██╔══██╗██║    ╚██╔╝  "
    echo " ╚██████╗██║  ██║██║  ██║██║  ██║███████╗██║   "
    echo "  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  "
    echo -e "${YELLOW}"
    echo "        HYSTERIA MANAGER - by CHARLY_TRICKS"
    echo "        Versión 1.0 | Soporte V1 + V2"
    echo -e "${CYAN}  ═══════════════════════════════════════════════${NC}"
    echo ""
}

# ── Dependencias ─────────────────────────────────────────────
instalar_dependencias() {
    echo -e "${YELLOW}[*] Instalando dependencias...${NC}"
    apt-get update -qq
    apt-get install -y -qq curl wget jq sqlite3 openssl net-tools lsof iptables-persistent cron > /dev/null 2>&1
    echo -e "${GREEN}[✓] Dependencias instaladas.${NC}"
}

# ── Inicializar BD ───────────────────────────────────────────
init_db() {
    local db="$1"
    mkdir -p "$CONFIG_DIR"
    sqlite3 "$db" "CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now')),
        expires_at TEXT,
        activo INTEGER DEFAULT 1
    );"
}

# ════════════════════════════════════════════════════════════
#   INSTALACIÓN HYSTERIA V1
# ════════════════════════════════════════════════════════════
instalar_v1() {
    mostrar_banner
    echo -e "${CYAN}[*] Instalando Hysteria V1...${NC}"
    instalar_dependencias

    # Descargar binario
    echo -e "${YELLOW}[*] Descargando Hysteria V1...${NC}"
    wget -q --show-progress -O "$BIN_V1" \
        "https://github.com/HyNetwork/hysteria/releases/download/v1.3.5/hysteria-linux-amd64"
    chmod +x "$BIN_V1"

    # Generar certificados
    echo -e "${YELLOW}[*] Generando certificados SSL...${NC}"
    mkdir -p "$CONFIG_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$CONFIG_DIR/v1.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$CONFIG_DIR/v1.key" \
        -out "$CONFIG_DIR/v1.crt" -subj "/CN=bing.com" 2>/dev/null

    # Pedir datos
    echo -e "${YELLOW}"
    read -p "  Puerto UDP: " puerto
    read -p "  Obfuscación (obfs): " obfs
    read -p "  Velocidad subida (Mbps): " up
    read -p "  Velocidad bajada (Mbps): " down
    echo -e "${NC}"

    # Inicializar BD
    init_db "$DB_V1"

    # Crear config
    cat > "$CONFIG_V1" <<EOF
{
    "listen": ":$puerto",
    "protocol": "udp",
    "cert": "$CONFIG_DIR/v1.crt",
    "key": "$CONFIG_DIR/v1.key",
    "up": "$up Mbps",
    "up_mbps": $up,
    "down": "$down Mbps",
    "down_mbps": $down,
    "disable_udp": false,
    "obfs": "$obfs",
    "auth": {
        "mode": "passwords",
        "config": []
    }
}
EOF

    # Servicio systemd
    cat > /etc/systemd/system/hysteria-v1.service <<EOF
[Unit]
Description=Hysteria V1 Server - CHARLY_TRICKS
After=network.target

[Service]
User=root
ExecStart=$BIN_V1 server --config $CONFIG_V1 --log-level 0
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria-v1 > /dev/null 2>&1
    systemctl start hysteria-v1

    # Abrir puerto
    iptables -I INPUT -p udp --dport "$puerto" -j ACCEPT
    iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}[✓] Hysteria V1 instalado en puerto $puerto${NC}"
    log "Hysteria V1 instalado en puerto $puerto"
    send_telegram "✅ <b>Hysteria V1 instalado</b>%0APuerto: $puerto%0AServidor: $(curl -s ipv4.icanhazip.com)"
    sleep 2
}

# ════════════════════════════════════════════════════════════
#   INSTALACIÓN HYSTERIA V2
# ════════════════════════════════════════════════════════════
instalar_v2() {
    mostrar_banner
    echo -e "${CYAN}[*] Instalando Hysteria V2...${NC}"
    instalar_dependencias

    # Descargar binario V2
    echo -e "${YELLOW}[*] Descargando Hysteria V2 (última versión)...${NC}"
    LATEST=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | jq -r '.tag_name')
    wget -q --show-progress -O "$BIN_V2" \
        "https://github.com/apernet/hysteria/releases/download/$LATEST/hysteria-linux-amd64"
    chmod +x "$BIN_V2"

    # Generar certificados
    echo -e "${YELLOW}[*] Generando certificados SSL...${NC}"
    mkdir -p "$CONFIG_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$CONFIG_DIR/v2.key" 2>/dev/null
    openssl req -new -x509 -days 36500 -key "$CONFIG_DIR/v2.key" \
        -out "$CONFIG_DIR/v2.crt" -subj "/CN=bing.com" 2>/dev/null

    # Pedir datos
    echo -e "${YELLOW}"
    read -p "  Puerto UDP: " puerto
    read -p "  Contraseña obfs: " obfs
    read -p "  Velocidad subida (Mbps): " up
    read -p "  Velocidad bajada (Mbps): " down
    echo -e "${NC}"

    # Inicializar BD
    init_db "$DB_V2"

    # Crear config YAML V2
    cat > "$CONFIG_V2" <<EOF
listen: :$puerto

tls:
  cert: $CONFIG_DIR/v2.crt
  key: $CONFIG_DIR/v2.key

obfs:
  type: salamander
  salamander:
    password: $obfs

bandwidth:
  up: ${up} mbps
  down: ${down} mbps

auth:
  type: userpass
  userpass: {}
EOF

    # Servicio systemd
    cat > /etc/systemd/system/hysteria-v2.service <<EOF
[Unit]
Description=Hysteria V2 Server - CHARLY_TRICKS
After=network.target

[Service]
User=root
ExecStart=$BIN_V2 server --config $CONFIG_V2
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria-v2 > /dev/null 2>&1
    systemctl start hysteria-v2

    # Abrir puerto
    iptables -I INPUT -p udp --dport "$puerto" -j ACCEPT
    iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}[✓] Hysteria V2 instalado en puerto $puerto${NC}"
    log "Hysteria V2 instalado en puerto $puerto"
    send_telegram "✅ <b>Hysteria V2 instalado</b>%0APuerto: $puerto%0AServidor: $(curl -s ipv4.icanhazip.com)"
    sleep 2
}

# ════════════════════════════════════════════════════════════
#   GESTIÓN DE USUARIOS
# ════════════════════════════════════════════════════════════
seleccionar_version() {
    echo -e "${YELLOW}  ¿Qué versión?${NC}"
    echo "  1) Hysteria V1"
    echo "  2) Hysteria V2"
    read -p "  Opción: " ver
    if [ "$ver" = "1" ]; then
        echo "v1"
    else
        echo "v2"
    fi
}

actualizar_config_usuarios() {
    local ver="$1"
    if [ "$ver" = "v1" ]; then
        local users=$(sqlite3 "$DB_V1" "SELECT username || ':' || password FROM users WHERE activo=1 AND (expires_at IS NULL OR expires_at > datetime('now'));")
        local arr=$(echo "$users" | awk -F'\n' '{for(i=1;i<=NF;i++) if($i!="") printf "\"" $i "\"" (i==NF ? "" : ",")}')
        jq ".auth.config = [$arr]" "$CONFIG_V1" > "${CONFIG_V1}.tmp" && mv "${CONFIG_V1}.tmp" "$CONFIG_V1"
        systemctl restart hysteria-v1 2>/dev/null
    else
        # V2: reconstruir sección userpass
        local userpass=$(sqlite3 "$DB_V2" "SELECT username, password FROM users WHERE activo=1 AND (expires_at IS NULL OR expires_at > datetime('now'));" | \
            awk -F'|' '{print "  "$1": "$2}' | paste -sd$'\n' -)
        # Reemplazar sección userpass en yaml
        python3 -c "
import re, sys
with open('$CONFIG_V2', 'r') as f:
    content = f.read()
users_block = '''auth:
  type: userpass
  userpass:
$(sqlite3 $DB_V2 'SELECT \"    \" || username || \": \" || password FROM users WHERE activo=1 AND (expires_at IS NULL OR expires_at > datetime(\"now\"));')'''
content = re.sub(r'auth:.*', users_block, content, flags=re.DOTALL)
with open('$CONFIG_V2', 'w') as f:
    f.write(content)
" 2>/dev/null
        systemctl restart hysteria-v2 2>/dev/null
    fi
}

agregar_usuario() {
    mostrar_banner
    echo -e "${CYAN}  ── AGREGAR USUARIO ──${NC}"
    local ver=$(seleccionar_version)
    local db=$( [ "$ver" = "v1" ] && echo "$DB_V1" || echo "$DB_V2" )

    echo -e "${YELLOW}"
    read -p "  Usuario: " username
    read -p "  Contraseña: " password
    read -p "  ¿Días de expiración? (0 = sin límite): " dias
    echo -e "${NC}"

    if [ "$dias" -gt 0 ] 2>/dev/null; then
        expires="datetime('now', '+${dias} days')"
        expires_show=$(date -d "+${dias} days" '+%Y-%m-%d')
    else
        expires="NULL"
        expires_show="Sin límite"
    fi

    sqlite3 "$db" "INSERT INTO users (username, password, expires_at) VALUES ('$username', '$password', $expires);" 2>/dev/null

    if [ $? -eq 0 ]; then
        actualizar_config_usuarios "$ver"
        echo -e "${GREEN}  [✓] Usuario '$username' agregado. Expira: $expires_show${NC}"
        log "Usuario $username agregado ($ver) - Expira: $expires_show"
        send_telegram "👤 <b>Nuevo usuario</b>%0AUsuario: $username%0AVersión: Hysteria $ver%0AExpira: $expires_show"
    else
        echo -e "${RED}  [✗] Error: El usuario ya existe.${NC}"
    fi
    sleep 2
}

editar_usuario() {
    mostrar_banner
    echo -e "${CYAN}  ── EDITAR USUARIO ──${NC}"
    local ver=$(seleccionar_version)
    local db=$( [ "$ver" = "v1" ] && echo "$DB_V1" || echo "$DB_V2" )

    echo -e "${YELLOW}"
    read -p "  Usuario a editar: " username
    read -p "  Nueva contraseña: " password
    read -p "  Nuevos días de expiración (0 = sin límite): " dias
    echo -e "${NC}"

    if [ "$dias" -gt 0 ] 2>/dev/null; then
        expires="datetime('now', '+${dias} days')"
        expires_show=$(date -d "+${dias} days" '+%Y-%m-%d')
    else
        expires="NULL"
        expires_show="Sin límite"
    fi

    sqlite3 "$db" "UPDATE users SET password='$password', expires_at=$expires WHERE username='$username';"

    if [ $? -eq 0 ]; then
        actualizar_config_usuarios "$ver"
        echo -e "${GREEN}  [✓] Usuario '$username' actualizado.${NC}"
        log "Usuario $username editado ($ver)"
    else
        echo -e "${RED}  [✗] Error al editar usuario.${NC}"
    fi
    sleep 2
}

eliminar_usuario() {
    mostrar_banner
    echo -e "${CYAN}  ── ELIMINAR USUARIO ──${NC}"
    local ver=$(seleccionar_version)
    local db=$( [ "$ver" = "v1" ] && echo "$DB_V1" || echo "$DB_V2" )

    echo -e "${YELLOW}"
    read -p "  Usuario a eliminar: " username
    echo -e "${NC}"

    sqlite3 "$db" "DELETE FROM users WHERE username='$username';"

    if [ $? -eq 0 ]; then
        actualizar_config_usuarios "$ver"
        echo -e "${GREEN}  [✓] Usuario '$username' eliminado.${NC}"
        log "Usuario $username eliminado ($ver)"
        send_telegram "🗑️ <b>Usuario eliminado</b>%0AUsuario: $username%0AVersión: Hysteria $ver"
    else
        echo -e "${RED}  [✗] Error al eliminar usuario.${NC}"
    fi
    sleep 2
}

mostrar_usuarios() {
    mostrar_banner
    echo -e "${CYAN}  ── LISTA DE USUARIOS ──${NC}"
    local ver=$(seleccionar_version)
    local db=$( [ "$ver" = "v1" ] && echo "$DB_V1" || echo "$DB_V2" )

    echo -e "${YELLOW}"
    printf "  %-20s %-20s %-12s %-20s\n" "USUARIO" "CONTRASEÑA" "ESTADO" "EXPIRA"
    echo "  ──────────────────────────────────────────────────────────────────"

    while IFS='|' read -r user pass activo expires; do
        if [ "$activo" = "1" ]; then
            estado="${GREEN}Activo${NC}"
        else
            estado="${RED}Inactivo${NC}"
        fi
        expires="${expires:-Sin límite}"
        printf "  ${CYAN}%-20s${NC} %-20s %b     %-20s\n" "$user" "$pass" "$estado" "$expires"
    done < <(sqlite3 "$db" "SELECT username, password, activo, COALESCE(expires_at,'Sin límite') FROM users;")

    echo -e "${NC}"
    read -p "  Presioná Enter para continuar..."
}

# ════════════════════════════════════════════════════════════
#   ESTADÍSTICAS
# ════════════════════════════════════════════════════════════
mostrar_estadisticas() {
    mostrar_banner
    echo -e "${CYAN}  ── ESTADÍSTICAS DEL SERVIDOR ──${NC}"
    echo ""

    local ip=$(curl -s ipv4.icanhazip.com 2>/dev/null)
    local uptime=$(uptime -p)
    local ram=$(free -m | awk '/Mem:/ {printf "%.0f MB usados / %.0f MB total", $3, $2}')
    local disco=$(df -h / | awk 'NR==2 {printf "%s usados / %s total", $3, $2}')
    local carga=$(cat /proc/loadavg | awk '{print $1, $2, $3}')

    echo -e "${YELLOW}  Sistema:${NC}"
    echo -e "  IP Pública   : ${GREEN}$ip${NC}"
    echo -e "  Uptime       : ${GREEN}$uptime${NC}"
    echo -e "  RAM          : ${GREEN}$ram${NC}"
    echo -e "  Disco        : ${GREEN}$disco${NC}"
    echo -e "  Carga CPU    : ${GREEN}$carga${NC}"
    echo ""

    echo -e "${YELLOW}  Hysteria V1:${NC}"
    if systemctl is-active --quiet hysteria-v1; then
        local u_v1=$(sqlite3 "$DB_V1" "SELECT COUNT(*) FROM users WHERE activo=1;" 2>/dev/null || echo "0")
        local e_v1=$(sqlite3 "$DB_V1" "SELECT COUNT(*) FROM users WHERE expires_at < datetime('now') AND expires_at IS NOT NULL;" 2>/dev/null || echo "0")
        echo -e "  Estado       : ${GREEN}● Activo${NC}"
        echo -e "  Usuarios     : ${GREEN}$u_v1 activos | $e_v1 expirados${NC}"
    else
        echo -e "  Estado       : ${RED}● Inactivo${NC}"
    fi
    echo ""

    echo -e "${YELLOW}  Hysteria V2:${NC}"
    if systemctl is-active --quiet hysteria-v2; then
        local u_v2=$(sqlite3 "$DB_V2" "SELECT COUNT(*) FROM users WHERE activo=1;" 2>/dev/null || echo "0")
        local e_v2=$(sqlite3 "$DB_V2" "SELECT COUNT(*) FROM users WHERE expires_at < datetime('now') AND expires_at IS NOT NULL;" 2>/dev/null || echo "0")
        echo -e "  Estado       : ${GREEN}● Activo${NC}"
        echo -e "  Usuarios     : ${GREEN}$u_v2 activos | $e_v2 expirados${NC}"
    else
        echo -e "  Estado       : ${RED}● Inactivo${NC}"
    fi
    echo ""
    read -p "  Presioná Enter para continuar..."
}

# ════════════════════════════════════════════════════════════
#   BACKUP
# ════════════════════════════════════════════════════════════
hacer_backup() {
    mostrar_banner
    echo -e "${CYAN}  ── BACKUP ──${NC}"
    mkdir -p "$BACKUP_DIR"
    local fecha=$(date '+%Y%m%d_%H%M%S')
    local archivo="$BACKUP_DIR/backup_$fecha.tar.gz"

    tar -czf "$archivo" "$CONFIG_DIR" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  [✓] Backup guardado en: $archivo${NC}"
        log "Backup creado: $archivo"
        send_telegram "💾 <b>Backup creado</b>%0AArchivo: backup_$fecha.tar.gz"
    else
        echo -e "${RED}  [✗] Error al crear backup.${NC}"
    fi
    sleep 2
}

listar_backups() {
    mostrar_banner
    echo -e "${CYAN}  ── BACKUPS DISPONIBLES ──${NC}"
    echo ""
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo -e "${YELLOW}  No hay backups.${NC}"
    echo ""
    read -p "  Presioná Enter para continuar..."
}

restaurar_backup() {
    mostrar_banner
    echo -e "${CYAN}  ── RESTAURAR BACKUP ──${NC}"
    listar_backups
    echo -e "${YELLOW}"
    read -p "  Nombre del archivo a restaurar: " archivo
    echo -e "${NC}"

    if [ -f "$BACKUP_DIR/$archivo" ]; then
        tar -xzf "$BACKUP_DIR/$archivo" -C / 2>/dev/null
        systemctl restart hysteria-v1 2>/dev/null
        systemctl restart hysteria-v2 2>/dev/null
        echo -e "${GREEN}  [✓] Backup restaurado correctamente.${NC}"
        log "Backup restaurado: $archivo"
    else
        echo -e "${RED}  [✗] Archivo no encontrado.${NC}"
    fi
    sleep 2
}

# ════════════════════════════════════════════════════════════
#   CONFIGURAR TELEGRAM
# ════════════════════════════════════════════════════════════
configurar_telegram() {
    mostrar_banner
    echo -e "${CYAN}  ── CONFIGURAR NOTIFICACIONES TELEGRAM ──${NC}"
    echo ""
    echo -e "${YELLOW}  Para obtener tu Token: habla con @BotFather en Telegram"
    echo -e "  Para obtener tu Chat ID: habla con @userinfobot${NC}"
    echo ""
    read -p "  Token del Bot: " token
    read -p "  Chat ID: " chat_id

    mkdir -p "$CONFIG_DIR"
    cat > "$TG_CONFIG" <<EOF
TG_TOKEN="$token"
TG_CHAT_ID="$chat_id"
EOF

    # Probar
    send_telegram "✅ <b>Hysteria Manager conectado</b>%0ALas notificaciones están activas."
    echo -e "${GREEN}  [✓] Telegram configurado. Se envió un mensaje de prueba.${NC}"
    sleep 2
}

# ════════════════════════════════════════════════════════════
#   EXPIRACIÓN AUTOMÁTICA (CRON)
# ════════════════════════════════════════════════════════════
configurar_cron_expiracion() {
    # Script que corre cada hora para desactivar usuarios expirados
    cat > /usr/local/bin/hysteria_expiry.sh <<'EXPIRY'
#!/bin/bash
DB_V1="/etc/hysteria/users_v1.db"
DB_V2="/etc/hysteria/users_v2.db"
TG_CONFIG="/etc/hysteria/telegram.conf"

send_tg() {
    if [ -f "$TG_CONFIG" ]; then
        source "$TG_CONFIG"
        curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
            -d "chat_id=$TG_CHAT_ID" -d "text=$1" -d "parse_mode=HTML" > /dev/null 2>&1
    fi
}

for db in "$DB_V1" "$DB_V2"; do
    [ ! -f "$db" ] && continue
    expired=$(sqlite3 "$db" "SELECT username FROM users WHERE activo=1 AND expires_at IS NOT NULL AND expires_at < datetime('now');")
    for user in $expired; do
        sqlite3 "$db" "UPDATE users SET activo=0 WHERE username='$user';"
        send_tg "⏰ <b>Usuario expirado</b>%0AUsuario: $user"
    done
done

# Actualizar configs
if [ -f "/etc/hysteria/config_v1.json" ]; then
    users=$(sqlite3 "$DB_V1" "SELECT username || ':' || password FROM users WHERE activo=1;" 2>/dev/null)
    arr=$(echo "$users" | awk -F'\n' '{for(i=1;i<=NF;i++) if($i!="") printf "\"" $i "\"" (i==NF ? "" : ",")}')
    jq ".auth.config = [$arr]" /etc/hysteria/config_v1.json > /etc/hysteria/config_v1.json.tmp && \
        mv /etc/hysteria/config_v1.json.tmp /etc/hysteria/config_v1.json
    systemctl restart hysteria-v1 2>/dev/null
fi
EXPIRY

    chmod +x /usr/local/bin/hysteria_expiry.sh

    # Agregar al cron si no existe
    if ! crontab -l 2>/dev/null | grep -q "hysteria_expiry"; then
        (crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/hysteria_expiry.sh") | crontab -
        echo -e "${GREEN}  [✓] Expiración automática configurada (cada hora).${NC}"
    fi
}

# ════════════════════════════════════════════════════════════
#   REINSTALAR MANAGER
# ════════════════════════════════════════════════════════════
instalar_comando_hysteria() {
    cp "$0" "$MANAGER_PATH"
    chmod +x "$MANAGER_PATH"
    echo -e "${GREEN}  [✓] Comando 'hysteria' instalado. Podés ejecutarlo desde cualquier lugar.${NC}"
}

# ════════════════════════════════════════════════════════════
#   REINICIAR / DETENER SERVICIOS
# ════════════════════════════════════════════════════════════
gestionar_servicios() {
    mostrar_banner
    echo -e "${CYAN}  ── GESTIÓN DE SERVICIOS ──${NC}"
    echo ""
    echo -e "  ${YELLOW}1)${NC} Reiniciar Hysteria V1"
    echo -e "  ${YELLOW}2)${NC} Reiniciar Hysteria V2"
    echo -e "  ${YELLOW}3)${NC} Detener Hysteria V1"
    echo -e "  ${YELLOW}4)${NC} Detener Hysteria V2"
    echo -e "  ${YELLOW}5)${NC} Ver logs Hysteria V1"
    echo -e "  ${YELLOW}6)${NC} Ver logs Hysteria V2"
    echo -e "  ${YELLOW}0)${NC} Volver"
    echo ""
    read -p "  Opción: " op

    case $op in
        1) systemctl restart hysteria-v1 && echo -e "${GREEN}  [✓] V1 reiniciado.${NC}" ;;
        2) systemctl restart hysteria-v2 && echo -e "${GREEN}  [✓] V2 reiniciado.${NC}" ;;
        3) systemctl stop hysteria-v1 && echo -e "${YELLOW}  [!] V1 detenido.${NC}" ;;
        4) systemctl stop hysteria-v2 && echo -e "${YELLOW}  [!] V2 detenido.${NC}" ;;
        5) journalctl -u hysteria-v1 -n 50 --no-pager ;;
        6) journalctl -u hysteria-v2 -n 50 --no-pager ;;
    esac
    sleep 2
}

# ════════════════════════════════════════════════════════════
#   MENÚ PRINCIPAL
# ════════════════════════════════════════════════════════════
menu_principal() {
    while true; do
        mostrar_banner
        echo -e "  ${CYAN}── INSTALACIÓN ──────────────────────────${NC}"
        echo -e "  ${YELLOW}1)${NC}  Instalar Hysteria V1"
        echo -e "  ${YELLOW}2)${NC}  Instalar Hysteria V2"
        echo -e "  ${YELLOW}3)${NC}  Instalar ambas versiones"
        echo ""
        echo -e "  ${CYAN}── USUARIOS ─────────────────────────────${NC}"
        echo -e "  ${YELLOW}4)${NC}  Agregar usuario"
        echo -e "  ${YELLOW}5)${NC}  Editar usuario"
        echo -e "  ${YELLOW}6)${NC}  Eliminar usuario"
        echo -e "  ${YELLOW}7)${NC}  Ver usuarios"
        echo ""
        echo -e "  ${CYAN}── SISTEMA ──────────────────────────────${NC}"
        echo -e "  ${YELLOW}8)${NC}  Estadísticas"
        echo -e "  ${YELLOW}9)${NC}  Gestionar servicios"
        echo -e "  ${YELLOW}10)${NC} Configurar Telegram"
        echo ""
        echo -e "  ${CYAN}── BACKUP ───────────────────────────────${NC}"
        echo -e "  ${YELLOW}11)${NC} Hacer backup"
        echo -e "  ${YELLOW}12)${NC} Ver backups"
        echo -e "  ${YELLOW}13)${NC} Restaurar backup"
        echo ""
        echo -e "  ${RED}0)${NC}  Salir"
        echo -e "  ${CYAN}─────────────────────────────────────────${NC}"
        echo ""
        read -p "  Seleccioná una opción: " opcion

        case $opcion in
            1) instalar_v1 ;;
            2) instalar_v2 ;;
            3) instalar_v1; instalar_v2 ;;
            4) agregar_usuario ;;
            5) editar_usuario ;;
            6) eliminar_usuario ;;
            7) mostrar_usuarios ;;
            8) mostrar_estadisticas ;;
            9) gestionar_servicios ;;
            10) configurar_telegram ;;
            11) hacer_backup ;;
            12) listar_backups ;;
            13) restaurar_backup ;;
            0) echo -e "${CYAN}  ¡Hasta luego!${NC}"; exit 0 ;;
            *) echo -e "${RED}  Opción inválida.${NC}"; sleep 1 ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════
#   INICIO
# ════════════════════════════════════════════════════════════
mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
touch "$LOG_FILE"
configurar_cron_expiracion
instalar_comando_hysteria
menu_principal
