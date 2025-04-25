#!/bin/bash

# Ruta del script proxy (se descargará más adelante)
PROXY_SCRIPT_URL="https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/mccproxy/proxy.py"
API="http://45.33.63.196:7555/validate"

# Leer argumentos
KEY="$1"
ARG="$2"

# Verificar si se proporcionó la key y el argumento correcto
if [[ -z "$KEY" || "$ARG" != "--mccpanel" ]]; then
    echo "Uso: ./installer.sh MCC-KEY{xxxx-xxxx-xxxx-xxxx} --mccpanel"
    exit 1
fi

# Instalar jq para manejar JSON
apt update -y && apt install -y jq
command -v jq >/dev/null 2>&1 || { echo >&2 "jq no está instalado correctamente. Abortando..."; exit 1; }

# Validar la key vía API
RESPUESTA=$(curl -s "$API/$(echo $KEY | jq -s -R -r @uri)")
VALIDA=$(echo "$RESPUESTA" | grep -o '"valida":true')

if [[ -z "$VALIDA" ]]; then
    echo -e "KEY inválida:"
    echo "$RESPUESTA"
    exit 1
fi

echo "KEY válida. Continuando instalación..."

# Instalar dependencias
apt update -y && apt install -y python3 python3-pip wget curl dropbear

# Crear directorio para proxy y descargarlo
mkdir -p /etc/mccproxy
wget -q -O /etc/mccproxy/proxy.py "$PROXY_SCRIPT_URL"
chmod +x /etc/mccproxy/proxy.py

# Crear archivo de puertos si no existe
if [[ ! -f /etc/mccproxy_ports ]]; then
    echo "80 443 8080" > /etc/mccproxy_ports
fi

# Crear servicio systemd para el proxy
cat <<EOF > /etc/systemd/system/mccproxy.service
[Unit]
Description=McCarthey Proxy TCP
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/mccproxy/proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Recargar y activar el servicio
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mccproxy
systemctl start mccproxy

# Mostrar información del VPS (fecha CA, IP, CPU, SO)
clear
echo "======================================"
echo "         McCarthey PANEL SSH"
echo "======================================"
echo "Fecha y hora (CA): $(TZ=America/Guatemala date)"
echo "IP pública: $(curl -s ifconfig.me)"
echo "CPUs: $(nproc)"
echo "Sistema: $(lsb_release -d | cut -f2)"
echo "--------------------------------------"
echo "Usa 'systemctl restart mccproxy' para reiniciar el proxy"
echo "Archivos: /etc/mccproxy/proxy.py y /etc/mccproxy_ports"
