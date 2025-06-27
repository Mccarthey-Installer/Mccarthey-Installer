#!/bin/bash

# Actualizar lista de paquetes e instalar actualizaciones
apt update -y && apt upgrade -y

# Configurar zona horaria a America/El_Salvador
timedatectl set-timezone America/El_Salvador

# Si está instalado needrestart, ejecutar para reiniciar servicios
if command -v needrestart >/dev/null; then
    needrestart -r a
fi

# Instalar paquetes necesarios
apt install -y curl unzip wget \
bsdmainutils screen nginx nload htop python3 python3-pip \
nodejs npm lsof psmisc socat bc net-tools cowsay \
nmap jq iptables openssh-server dropbear

# Configurar Dropbear para que escuche en el puerto 444
echo "/bin/bash" > /etc/shells
echo "/usr/sbin/dropbear" >> /etc/shells

# Habilitar y configurar Dropbear en el puerto 444
sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear || echo "DROPBEAR_PORT=444" >> /etc/default/dropbear

# Iniciar o reiniciar Dropbear
systemctl enable dropbear
systemctl restart dropbear

# Verificar que el puerto 444 está en escucha
echo -e "\nEstado del puerto 444:"
ss -tulnp | grep :444 || echo "⚠️ Dropbear no está escuchando en el puerto 444."
