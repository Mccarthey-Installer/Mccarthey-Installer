#!/bin/bash

# Colores
red='\e[1;91m'
green='\e[1;92m'
reset='\e[0m'

API="http://45.33.63.196:7555/validate"
KEY=""
PANEL=false

# Leer argumentos
for arg in "$@"; do
    if [[ $arg == MCC-KEY* ]]; then
        KEY="$arg"
    elif [[ $arg == "--mccpanel" ]]; then
        PANEL=true
    fi
done

# Si no se pasó la key, pedirla
if [[ -z "$KEY" ]]; then
    echo -e "${green}>> Bienvenido al instalador McCarthey${reset}"
    read -p "Ingresa tu MCC-KEY: " KEY
fi

# Validar la KEY
RESPUESTA=$(curl -s "$API/$(echo $KEY | jq -s -R -r @uri)")
VALIDA=$(echo "$RESPUESTA" | grep -o '"valida":true')

if [ -z "$VALIDA" ]; then
  echo -e "${red}KEY inválida: $(echo $RESPUESTA | jq -r .motivo)${reset}"
  exit 1
fi

echo -e "${green}KEY válida. Instalando entorno...${reset}"

# Actualizar sistema
apt update -y && apt upgrade -y

# Instalar dependencias
apt install -y python3 python3-pip screen sqlite3 wget curl jq

# Crear archivos necesarios
mkdir -p /etc/mccproxy
echo "80 443 8080" > /etc/mccproxy_ports

# Descargar proxy.py
wget -q https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/mccproxy/proxy.py -O /etc/mccproxy/proxy.py
chmod +x /etc/mccproxy/proxy.py

# Crear servicio systemd
cat <<EOF > /etc/systemd/system/mccproxy.service
[Unit]
Description=McCarthey Proxy
After=network.target

[Service]
ExecStart=/usr/bin/python3 /etc/mccproxy/proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable mccproxy
systemctl restart mccproxy

# Si se especificó el panel
if $PANEL; then
  echo -e "${green}Descargando y activando el panel...${reset}"
  wget -q https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/menu.sh -O /usr/local/bin/menu
  chmod +x /usr/local/bin/menu
  echo -e "${green}Panel instalado. Usa el comando: menu${reset}"
fi
