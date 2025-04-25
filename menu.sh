#!/bin/bash

API_PORT=40412
API_URL="http://localhost:$API_PORT/validate"
API_FILE="/root/telegram-bot/api.py"
DB_FILE="/root/telegram-bot/keys.db"

# Colores
GREEN="\e[92m"
RED="\e[91m"
YELLOW="\e[93m"
RESET="\e[0m"

function log_info() {
    echo -e "[ ${GREEN}INFO${RESET} ] $1"
}

function log_error() {
    echo -e "[ ${RED}ERROR${RESET} ] $1"
}

function log_warn() {
    echo -e "[ ${YELLOW}WARN${RESET} ] $1"
}

function validar_key() {
    local key="$1"
    local encoded_key
    encoded_key=$(python3 -c "import urllib.parse; print(urllib.parse.quote('''$key'''))")
    local respuesta
    respuesta=$(curl -s "$API_URL/$encoded_key")
    local valida
    valida=$(echo "$respuesta" | grep -o '"valida":true')
    local motivo
    motivo=$(echo "$respuesta" | sed -n 's/.*"motivo":"[^"]*".*/\1/p')

    if [[ -n "$valida" ]]; then
        log_info "KEY válida: $motivo"
    else
        log_error "KEY inválida: $motivo"
        exit 1
    fi
}

function instalar_dependencias() {
    log_info "Actualizando paquetes e instalando dependencias..."
    apt update -y && apt upgrade -y
    apt install -y python3 python3-pip sqlite3 wget curl net-tools
    pip3 install flask > /dev/null 2>&1
    log_info "Dependencias instaladas correctamente."
}

function configurar_api() {
    log_info "Configurando API Flask..."

    mkdir -p /root/telegram-bot

    if [[ ! -f "$API_FILE" ]]; then
        cat > "$API_FILE" << 'EOF'
#!/usr/bin/python3
from flask import Flask, jsonify
import sqlite3
from urllib.parse import unquote
from datetime import datetime, timedelta

app = Flask(__name__)
DB_PATH = '/root/telegram-bot/keys.db'

def validar_key(key):
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT key, origen, fecha, usada, ip FROM keys WHERE key = ?", (key,))
        resultado = cur.fetchone()
        conn.close()
        if not resultado:
            return {"valida": False, "motivo": "KEY no encontrada"}
        clave, origen, fecha_str, usada, ip = resultado
        fecha = datetime.fromisoformat(fecha_str.split('+')[0])
        expira = fecha + timedelta(hours=3)
        if datetime.utcnow() > expira:
            return {"valida": False, "motivo": "KEY expirada"}
        if usada:
            return {"valida": False, "motivo": "KEY ya usada"}
        return {"valida": True, "motivo": "KEY válida"}
    except Exception as e:
        return {"valida": False, "motivo": f"Error del servidor: {str(e)}"}

@app.route('/validate/<path:key>', methods=['GET'])
def validar(key):
    key = unquote(key)
    resultado = validar_key(key)
    return jsonify(resultado)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=40412)
EOF
        chmod +x "$API_FILE"
    else
        log_info "$API_FILE ya existe."
    fi
}

function iniciar_api() {
    log_info "Verificando estado de la API Flask..."
    if ss -tuln | grep -q ":$API_PORT"; then
        log_info "La API Flask ya está en ejecución."
    else
        log_info "Iniciando API Flask en puerto $API_PORT..."
        nohup python3 "$API_FILE" >/var/log/api_flask.log 2>&1 &
        sleep 3
        if ss -tuln | grep -q ":$API_PORT"; then
            log_info "API Flask iniciada correctamente."
        else
            log_error "No se pudo iniciar la API Flask. Error:"
            tail -n 10 /var/log/api_flask.log
            exit 1
        fi
    fi
}

function configurar_db() {
    if [[ ! -f "$DB_FILE" ]]; then
        log_info "Configurando base de datos SQLite..."
        sqlite3 "$DB_FILE" "CREATE TABLE keys (key TEXT PRIMARY KEY, origen TEXT, fecha TEXT, usada INTEGER, ip TEXT);"
        log_info "Base de datos creada correctamente."
    fi
}

function mostrar_panel() {
    echo -e "\n${GREEN}=== PANEL MCCARTHEY ===${RESET}"
    echo "[1] Mostrar IP"
    echo "[2] Ver CPU y RAM"
    echo "[3] Crear usuario SSH"
    echo "[0] Salir"
}

### PROCESO PRINCIPAL ###

KEY="$1"
ARG2="$2"

if [[ -z "$KEY" ]]; then
    log_error "Debes proporcionar una MCC-KEY."
    echo -e "Uso: ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} [--mccpanel]"
    exit 1
fi

instalar_dependencias
configurar_api
configurar_db
iniciar_api
validar_key "$KEY"

if [[ "$ARG2" == "--mccpanel" ]]; then
    mostrar_panel
fi
