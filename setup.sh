#!/bin/bash

# Colores para mensajes
verde="\e[32m"
rojo="\e[31m"
normal="\e[0m"

echo -e "${verde}➤ Actualizando paquetes...${normal}"
apt update -y && apt upgrade -y

echo -e "${verde}➤ Configurando zona horaria a America/El_Salvador...${normal}"
timedatectl set-timezone America/El_Salvador

# Reiniciar servicios si needrestart está instalado
if command -v needrestart >/dev/null; then
    echo -e "${verde}➤ Ejecutando needrestart...${normal}"
    needrestart -r a
fi

echo -e "${verde}➤ Instalando paquetes necesarios...${normal}"
apt install -y curl unzip wget \
bsdmainutils screen nginx nload htop python3 python3-pip \
nodejs npm lsof psmisc socat bc net-tools cowsay \
nmap jq iptables openssh-server dropbear

# Asegurar rutas de shells
echo "/bin/bash" > /etc/shells
echo "/usr/sbin/dropbear" >> /etc/shells

echo -e "${verde}➤ Configurando Dropbear en el puerto 444...${normal}"
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
if grep -q '^DROPBEAR_PORT=' /etc/default/dropbear; then
    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear
else
    echo "DROPBEAR_PORT=444" >> /etc/default/dropbear
fi

# Habilitar e iniciar Dropbear
systemctl enable dropbear
systemctl restart dropbear

# Verificar estado del puerto 444
echo -e "\n${verde}➤ Verificando puerto 444...${normal}"
if ss -tulnp | grep -q ':444'; then
    echo -e "${verde}✅ Dropbear está escuchando en el puerto 444.${normal}"
else
    echo -e "${rojo}⚠️ Dropbear NO está escuchando en el puerto 444.${normal}"
fi

# Ejecutar el instalador principal del panel McCarthey
echo -e "\n${verde}➤ Ejecutando el instalador McCarthey Panel...${normal}"
bash <(wget -qO- https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/setup.sh) --mccpanel

echo -e "\n${verde}✅ Instalación finalizada correctamente.${normal}"
