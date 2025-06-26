
#!/bin/bash

# Archivo de registros
REGISTROS="/root/registros.txt"

# Colores ANSI
VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[38;5;196m'
CIAN='\033[38;5;51m'
NC='\033[0m'

function barra_sistema() {
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')
    MEM_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
    MEM_PORC=$(awk "BEGIN {printf \"%.2f\", ($MEM_USO/$MEM_TOTAL)*100}")

    function human() {
        local value=$1
        if [ "$value" -ge 1024 ]; then
            awk "BEGIN {printf \"%.1fG\", $value/1024}"
        else
            echo "${value}M"
        fi
    }

    MEM_TOTAL_H=$(human "$MEM_TOTAL")
    MEM_LIBRE_H=$(human "$MEM_LIBRE")
    MEM_USO_H=$(human "$MEM_USO")

    CPU_PORC=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    CPU_PORC=$(awk "BEGIN {printf \"%.0f\", $CPU_PORC}")
    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "Desconocido")

    function crear_bateria() {
        local porcentaje=$1
        if [ "$porcentaje" -lt 20 ]; then echo -n "▁"
        elif [ "$porcentaje" -lt 40 ]; then echo -n "▂"
        elif [ "$porcentaje" -lt 60 ]; then echo -n "▃"
        elif [ "$porcentaje" -lt 80 ]; then echo -n "▅"
        else echo -n "▇"
        fi
    }

    BATERIA_RAM=$(crear_bateria "${MEM_PORC%.*}")
    BATERIA_CPU=$(crear_bateria "$CPU_PORC")

    IP_PUBLICA=$(curl -s ifconfig.me || wget -qO- ifconfig.me)
    FECHA_ACTUAL=$(TZ=America/Guatemala date +"%d/%m/%Y - %I:%M %p")

    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ∘ TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘  LIBRE: ${AMARILLO}${MEM_LIBRE_H}${NC} ∘ EN USO: ${AMARILLO}${MEM_USO_H}${NC}"
    echo -e " ∘ RAM: ${AMARILLO}${BATERIA_RAM} ${MEM_PORC}%${NC} ∘ CPU: ${AMARILLO}${BATERIA_CPU} ${CPU_PORC}%${NC} ∘ MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ∘ IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e " ${ROJO}Mccarthey ♥️${NC}"
}

function crear_usuario() {
    read -p "Usuario: " USR
    read -p "Contraseña: " PASS
    read -p "Duración (días): " DIAS

    useradd -e $(date -d "$DIAS days" +%Y-%m-%d) -s /bin/false -M $USR
    echo "$USR:$PASS" | chpasswd
    echo "$USR $(date +"%d/%m/%Y %H:%M")" >> "$REGISTROS"
    echo -e "${VERDE}✓ Usuario creado: $USR${NC}"
    sleep 2
}

function ver_registros() {
    echo -e "${CIAN}REGISTROS DE USUARIOS:${NC}"
    cat "$REGISTROS"
    read -p "Presiona enter para continuar..."
}

function eliminar_usuario() {
    read -p "Usuario a eliminar: " USR
    userdel -f $USR && sed -i "/^$USR /d" "$REGISTROS"
    echo -e "${VERDE}✓ Usuario $USR eliminado.${NC}"
    sleep 2
}

function eliminar_todos_usuarios() {
    echo -e "${ROJO}⚠ Esto eliminará TODOS los usuarios registrados en el panel.${NC}"
    read -p "¿Estás seguro? [s/n]: " CONF
    if [[ "$CONF" == "s" ]]; then
        for user in $(cut -d' ' -f1 "$REGISTROS"); do
            userdel -f "$user"
        done
        > "$REGISTROS"
        echo -e "${VERDE}✓ Todos los usuarios eliminados.${NC}"
        sleep 2
    fi
}

function verificar_online() {
    echo -e "${CIAN}USUARIOS SSH ONLINE:${NC}"
    who | awk '{print $1}' | sort | uniq -c
    read -p "Presiona enter para continuar..."
}

function activar_protocolos() {
    while true; do
        clear
        echo -e "${VIOLETA}===== ACTIVAR PROTOCOLOS =====${NC}"
        echo -e "${AMARILLO}Aquí puedes activar servicios esenciales${NC}"
        echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "[1] Activar Dropbear en puerto 444"
        echo "[2] Iniciar Proxy WS/Directo (puerto 80 redirige a 444)"
        echo "[0] Volver al menú"
        echo -e "${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        read -p "Selecciona una opción: " opt
        case $opt in
            1)
                echo -e "\n${VERDE}[+] Instalando Dropbear...${NC}"
                apt install dropbear -y > /dev/null 2>&1
                echo "/bin/false" >> /etc/shells
                echo "/usr/sbin/nologin" >> /etc/shells
                sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear
                sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear
                echo 'DROPBEAR_EXTRA_ARGS="-p 444"' >> /etc/default/dropbear
                systemctl restart dropbear || service dropbear restart
                echo -e "${VERDE}[✓] Dropbear activado en puerto 444.${NC}"
                sleep 2
                ;;
            2)
                if ! pgrep dropbear > /dev/null; then
                    echo -e "${ROJO}[!] Dropbear no está activo.${NC}"
                    sleep 2
                    continue
                fi
                echo -e "\n${VERDE}[+] Configurando Proxy...${NC}"
                mkdir -p /etc/mccproxy
                wget -q https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/extras/proxy.sh -O /etc/mccproxy/proxy.sh
                chmod +x /etc/mccproxy/proxy.sh
                /etc/mccproxy/proxy.sh
                echo -e "${VERDE}[✓] Proxy WS configurado.${NC}"
                sleep 2
                ;;
            0) return ;;
            *) echo -e "${ROJO}Opción inválida!${NC}" ; sleep 1 ;;
        esac
    done
}

# Inicia el menú principal
while true; do
    clear
    barra_sistema
    echo
    echo -e "${VIOLETA}====== PANEL DE USUARIOS VPN/SSH ======${NC}"
    echo -e "${VERDE}1. Crear usuario${NC}"
    echo -e "${VERDE}2. Ver registros${NC}"
    echo -e "${VERDE}3. Eliminar usuario${NC}"
    echo -e "${VERDE}4. Eliminar TODOS los usuarios${NC}"
    echo -e "${VERDE}5. Verificar usuarios online${NC}"
    echo -e "${VERDE}6. Activar protocolos${NC}"
    echo -e "${VERDE}7. Salir${NC}"
    read -p "$(echo -e ${AMARILLO}Selecciona una opción: ${NC})" OPCION
    case $OPCION in
        1) crear_usuario ;;
        2) ver_registros ;;
        3) eliminar_usuario ;;
        4) eliminar_todos_usuarios ;;
        5) verificar_online ;;
        6) activar_protocolos ;;
        7) echo -e "${AZUL}Saliendo...${NC}"; exit 0 ;;
        *) echo -e "${ROJO}Opción inválida!${NC}"; read -p "Presiona Enter para continuar..." ;;
    esac
done
