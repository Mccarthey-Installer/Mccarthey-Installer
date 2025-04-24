#!/bin/bash

# Asegurar que el enlace simbólico /usr/bin/menu exista
setup_menu_command() {
    if [ ! -f /root/menu.sh ]; then
        echo -e "\e[1;31m[ ERROR ] /root/menu.sh no encontrado. Reinstala el panel.\e[0m"
        exit 1
    fi
    chmod +x /root/menu.sh
    if [ ! -L /usr/bin/menu ] || [ "$(readlink /usr/bin/menu)" != "/root/menu.sh" ]; then
        ln -sf /root/menu.sh /usr/bin/menu
        chmod +x /usr/bin/menu
    fi
}

# Ejecutar configuración inicial
setup_menu_command

# Función para validar la MCC-KEY y actualizar el repositorio
validar_key() {
    echo -e "\n\033[1;36m[ INFO ]\033[0m Descargando el instalador actualizado..."
    wget -q -O ./installer.sh https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/installer.sh
    if [ $? -ne 0 ] || [ ! -s ./installer.sh ]; then
        echo -e "\033[1;31m[ ERROR ] No se pudo descargar installer.sh. Verifica tu conexión.\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi
    chmod +x ./installer.sh
    echo -e "\033[1;96m[ OK ] installer.sh actualizado.\033[0m"

    # Solicitar nueva MCC-KEY
    echo -e "\n\033[1;36m[ INFO ] Ingresa tu nueva MCC-KEY:\033[0m"
    read -p "> " NEW_KEY

    # Validar formato MCC-KEY
    if [[ ! $NEW_KEY =~ ^MCC-KEY\{[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}\}$ ]]; then
        echo -e "\033[1;31m[ ERROR ] MCC-KEY inválida. Formato esperado: MCC-KEY{XXXX-XXXX-XXXX-XXXX}\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi

    # Ejecutar installer.sh con la nueva key
    echo -e "\n\033[1;36m[ INFO ] Ejecutando el script actualizado...\033[0m"
    ./installer.sh --mccpanel --proxy "$NEW_KEY"
    if [ $? -ne 0 ]; then
        echo -e "\033[1;31m[ ERROR ] Error al ejecutar el script actualizado.\033[0m"
        read -p "Presiona enter para continuar..."
        return 1
    fi

    echo -e "\n\033[1;96m[ OK ] Actualización completada. Reiniciando el panel...\033[0m"
    exec /usr/bin/menu
}

# Función para formatear tiempo en hh:mm
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    printf "%02dh %02dm" $hours $minutes
}

# Función para obtener tiempo conectado promedio de un usuario
get_user_connection_time() {
    local usuario=$1
    local times=()
    while IFS= read -r etime; do
        if [[ -n "$etime" ]]; then
            if [[ "$etime" =~ ([0-9]+)-([0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
                days=${BASH_REMATCH[1]}
                time=${BASH_REMATCH[2]}
                IFS=: read h m s <<< "$time"
                seconds=$((days*86400 + h*3600 + m*60 + s))
            elif [[ "$etime" =~ ([0-9]{2}):([0-9]{2}) ]]; then
                h=${BASH_REMATCH[1]}
                m=${BASH_REMATCH[2]}
                seconds=$((h*3600 + m*60))
            else
                seconds=0
            fi
            times+=("$seconds")
        fi
    done < <(ps -u "$usuario" -o etime --no-headers 2>/dev/null | grep -v '^$')
    
    if [ ${#times[@]} -eq 0 ]; then
        echo "00h 00m"
        return
    fi
    
    local total=0
    for t in "${times[@]}"; do
        total=$((total + t))
    done
    local avg=$((total / ${#times[@]}))
    format_time "$avg"
}

# Función para contar conexiones por usuario
get_user_connections() {
    local usuario=$1
    who | grep "^$usuario " | wc -l
}

# Función para verificar y gestionar límites de conexiones
check_user_limits() {
    local usuarios_file="/root/usuarios_registrados.txt"
    local multi_log="/root/multi_onlines.log"
    local locked_file="/root/locked_users.txt"
    touch "$locked_file"
    
    if [[ ! -s "$usuarios_file" ]]; then
        return
    fi
    
    while IFS=: read -r usuario _ limite _ _; do
        if ! id "$usuario" >/dev/null 2>&1; then
            continue
        fi
        local conexiones=$(get_user_connections "$usuario")
        local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        
        local is_locked=$(grep "^$usuario$" "$locked_file")
        
        if [ "$conexiones" -gt "$limite" ]; then
            if [ -z "$is_locked" ]; then
                usermod -L "$usuario" 2>/dev/null
                echo "$usuario" >> "$locked_file"
                printf "%-5s %-12s %-14s %-30s\n" "" "$usuario" "$conexiones/$limite" "$timestamp" >> "$multi_log"
                echo -e "\033[1;31m[ WARN ] Usuario $usuario bloqueado: $conexiones conexiones exceden límite de $limite.\033[0m" >&2
            fi
        elif [ "$conexiones" -le "$limite" ] && [ -n "$is_locked" ]; then
            usermod -U "$usuario" 2>/dev/null
            sed -i "/^$usuario$/d" "$locked_file"
            echo -e "\033[1;32m[ INFO ] Usuario $usuario desbloqueado: $conexiones conexiones dentro del límite de $limite.\033[0m" >&2
        fi
    done < "$usuarios_file"
}

# Función para mostrar dispositivos online
show_online_devices() {
    clear
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "          \e[1;33mDISPOSITIVOS ONLINE - MCCARTHEY PANEL\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[1;35m$(printf '%-14s %-14s %-15s' 'USUARIO' 'CONEXIONES' 'TIEMPO CONECTADO')\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    local total_conexiones=0
    local USUARIOS_FILE="/root/usuarios_registrados.txt"
    
    if [[ -s "$USUARIOS_FILE" ]]; then
        while IFS=: read -r usuario _ limite _ _; do
            if id "$usuario" >/dev/null 2>&1; then
                local conexiones
                conexiones=$(get_user_connections "$usuario")
                local tiempo
                tiempo=$(get_user_connection_time "$usuario")
                printf "%-14s %-14s %-15s\n" "$usuario" "$conexiones/$limite" "$tiempo"
                total_conexiones=$((total_conexiones + conexiones))
            fi
        done < "$USUARIOS_FILE"
    fi
    
    if [ "$total_conexiones" -eq 0 ]; then
        echo -e "\e[1;31mNo hay dispositivos conectados.\e[0m"
    fi
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[1;91mTOTAL DISPOSITIVOS ONLINE: $total_conexiones\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    read -p "Presiona enter para volver al panel principal..."
}

# Variables generales
fecha=$(TZ=America/El_Salvador date +"%a %d/%m/%Y - %I:%M:%S %p %Z")
ip=$(hostname -I | awk '{print $1}')
cpus=$(nproc)
so=$(lsb_release -d | cut -f2)

hour=$(TZ=America/El_Salvador date +%H)
if [ $hour -ge 0 -a $hour -lt 12 ]; then
    saludo="Buenos días 🌞"
elif [ $hour -ge 12 -a $hour -lt 19 ]; then
    saludo="Buenas tardes ☀️"
else
    saludo="Buenas Noches 🌙"
fi

USUARIOS_FILE="/root/usuarios_registrados.txt"
MULTI_ONLINES_LOG="/root/multi_onlines.log"
DEBUG_LOG="/root/debug_conexiones.log"
LOCKED_USERS_FILE="/root/locked_users.txt"

touch "$MULTI_ONLINES_LOG"
touch "$DEBUG_LOG"
touch "$LOCKED_USERS_FILE"

if [[ -s "$USUARIOS_FILE" ]]; then
    usuarios_registrados=$(grep -c "^[^:]*:" "$USUARIOS_FILE")
else
    usuarios_registrados=0
fi

# Calcular total de conexiones de usuarios registrados
get_total_connections() {
    local total=0
    if [[ -s "$USUARIOS_FILE" ]]; then
        while IFS=: read -r usuario _ _ _ _; do
            if id "$usuario" >/dev/null 2>&1; then
                local conexiones
                conexiones=$(get_user_connections "$usuario")
                total=$((total + conexiones))
            fi
        done < "$USUARIOS_FILE"
    fi
    echo "$total"
}

devices_online=$(get_total_connections)

read total used free shared buff_cache available <<< $(free -m | awk '/^Mem:/ {print $2, $3, $4, $5, $6, $7}')
cpu_uso=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
cpu_uso_fmt=$(awk "BEGIN {printf \"%.1f%%\", $cpu_uso}")
ram_porc=$(awk "BEGIN {printf \"%.2f%%\", ($used/$total)*100}")

if [ "$total" -ge 1024 ]; then
    ram_total=$(awk "BEGIN {printf \"%.1fG\", $total/1024}")
    ram_libre=$(awk "BEGIN {printf \"%.1fG\", $available/1024}")
else
    ram_total="${total}M"
    ram_libre="${available}M"
fi

ram_usada=$(awk "BEGIN {printf \"%.0fM\", $used}")
ram_cache=$(awk "BEGIN {printf \"%.0fM\", $buff_cache}")

while true; do
    check_user_limits
    
    clear
    devices_online=$(get_total_connections)
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "          \e[1;33mPANEL😀🤩 OFICIAL MCCARTHEY💕\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e "\e[1;35m$saludo\e[0m"
    echo -e " \e[1;35mFECHA       :\e[0m \e[1;93m$fecha\e[0m"
    echo -e " \e[1;35mIP VPS      :\e[0m \e[1;93m$ip\e[0m"
    echo -e " \e[1;35mCPU's       :\e[0m \e[1;93m$cpus\e[0m"
    echo -e " \e[1;91mDISPOSITIVOS ON:\e[0m \e[1;91m$devices_online onlines.\e[0m"
    echo -e " \e[1;35mS.O         :\e[0m \e[1;93m$so\e[0m"
    echo -e " \e[1;35mUsuarios registrados:\e[0m \e[1;93m$usuarios_registrados\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;96m∘ TOTAL: $ram_total  ∘ LIBRE: $ram_libre  ∘ EN USO: $ram_usada\e[0m"
    echo -e " \e[1;96m∘ U/RAM: $ram_porc   ∘ U/CPU: $cpu_uso_fmt  ∘ BUFFER: $ram_cache\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e " \e[1;33m[1] ➮ CREAR NUEVO USUARIO SSH\e[0m"
    echo -e " \e[1;33m[2] ➮ ACTUALIZAR MCC-KEY\e[0m"
    echo -e " \e[1;33m[3] ➮ USUARIOS REGISTRADOS\e[0m"
    echo -e " \e[1;33m[4] ➮ ELIMINAR USUARIOS\e[0m"
    echo -e " \e[1;33m[5] ➮ SALIR\e[0m"
    echo -e " \e[1;33m[6] 💕 ➮ COLOCAR PUERTOS\e[0m"
    echo -e " \e[1;33m[7] 💕 ➮ VER DISPOSITIVOS ONLINE\e[0m"
    echo -e " \e[1;33m[8] 💕 ➮ VER MULTI ONLINES\e[0m"
    echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
    echo -e -n "\e[1;33m► 🌞Elige una opción: \e[0m"
    read opc

    case $opc in
        1)
            read -p $'\e[1;95mNombre de usuario: \e[0m' USUARIO
            if id "$USUARIO" >/dev/null 2>&1; then
                echo ""
                echo -e "\e[1;31mEl usuario $USUARIO ya existe en el sistema.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi
            if grep -q "^$USUARIO:" "$USUARIOS_FILE" 2>/dev/null; then
                echo ""
                echo -e "\e[1;31mEl usuario $USUARIO ya está registrado en el archivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi
            read -p $'\e[1;95mContraseña: \e[0m' PASSWORD
            read -p $'\e[1;95mLímite de conexiones: \e[0m' LIMITE
            read -p $'\e[1;95mDías de validez: \e[0m' DIAS

            if [[ -z "$USUARIO" || -z "$PASSWORD" || -z "$LIMITE" || -z "$DIAS" ]]; then
                echo ""
                echo -e "\e[1;31mPor favor complete todos los datos.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            if ! [[ "$LIMITE" =~ ^[0-9]+$ ]] || [ "$LIMITE" -lt 1 ]; then
                echo ""
                echo -e "\e[1;31mEl límite de conexiones debe ser un número positivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            if ! [[ "$DIAS" =~ ^[0-9]+$ ]] || [ "$DIAS" -lt 1 ]; then
                echo ""
                echo -e "\e[1;31mLos días de validez deben ser un número positivo.\e[0m"
                echo ""
                read -p "Presiona enter para volver al panel principal..."
                continue
            fi

            FECHA_EXPIRACION=$(date -d "$DIAS days" +"%d/ de %B")
            useradd -e $(date -d "$DIAS days" +%Y-%m-%d) -s /bin/false -M "$USUARIO"
            echo "$USUARIO:$PASSWORD" | chpasswd
            echo "$USUARIO:$PASSWORD:$LIMITE:$FECHA_EXPIRACION:$DIAS" >> "$USUARIOS_FILE"
            echo ""
            echo -e "\e[1;96mUsuario creado con éxito:\e[0m"
            echo ""
            echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
            printf "%-12s %-14s %-10s %-15s %-5s\n" "$USUARIO" "$PASSWORD" "$LIMITE" "$FECHA_EXPIRACION" "$DIAS"
            echo ""
            read -p "Presiona enter para continuar..."
            ;;
        2)
            validar_key
            ;;
        3)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mUSUARIOS REGISTRADOS\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$USUARIOS_FILE" ]]; then
                echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
                while IFS=: read -r usuario password limite caduca dias; do
                    if id "$usuario" >/dev/null 2>&1; then
                        printf "%-12s %-14s %-10s %-15s %-5s\n" "$usuario" "$password" "$limite" "$caduca" "$dias"
                    else
                        sed -i "/^$usuario:/d" "$USUARIOS_FILE"
                    fi
                done < "$USUARIOS_FILE"
                if [[ ! -s "$USUARIOS_FILE" ]]; then
                    echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
                fi
            else
                echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            read -p "Presiona enter para volver al panel principal..."
            ;;
        4)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mELIMINAR USUARIOS\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$USUARIOS_FILE" ]]; then
                echo -e "\e[1;35m$(printf '%-12s %-14s %-10s %-15s %-5s' 'USUARIO' 'CONTRASEÑA' 'LIMITE' 'CADUCA' 'DIAS')\e[0m"
                while IFS=: read -r usuario password limite caduca dias; do
                    if id "$usuario" >/dev/null 2>&1; then
                        printf "%-12s %-14s %-10s %-15s %-5s\n" "$usuario" "$password" "$limite" "$caduca" "$dias"
                    else
                        sed -i "/^$usuario:/d" "$USUARIOS_FILE"
                    fi
                done < "$USUARIOS_FILE"
                if [[ ! -s "$USUARIOS_FILE" ]]; then
                    echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
                fi
            else
                echo -e "\e[1;31mLista vacía. No hay usuarios registrados.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "\e[1;33m[1] Eliminar un usuario específico\e[0m"
            echo -e "\e[1;33m[2] Eliminar todos los usuarios\e[0m"
            echo -e "\e[1;33m[3] Volver al panel principal\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e -n "\e[1;33m► Elige una opción: \e[0m"
            read del_opc

            case $del_opc in
                1)
                    read -p "Nombre del usuario a eliminar: " USUARIO_DEL
                    if [[ -z "$USUARIO_DEL" ]]; then
                        echo -e "\e[1;31mPor favor ingrese un nombre de usuario.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    if ! id "$USUARIO_DEL" >/dev/null 2>&1; then
                        echo -e "\e[1;31mEl usuario $USUARIO_DEL no existe.\e[0m"
                        sed -i "/^$USUARIO_DEL:/d" "$USUARIOS_FILE" 2>/dev/null
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    echo -e "\e[1;33m¿Estás seguro de eliminar al usuario $USUARIO_DEL? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        userdel -r "$USUARIO_DEL" 2>/dev/null
                        sed -i "/^$USUARIO_DEL:/d" "$USUARIOS_FILE"
                        sed -i "/^$USUARIO_DEL$/d" "$LOCKED_USERS_FILE"
                        echo -e "\e[1;96mUsuario $USUARIO_DEL eliminado con éxito.\e[0m"
                    else
                        echo -e "\e[1;31mEliminación cancelada.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    ;;
                2)
                    echo -e "\e[1;33m¿Estás seguro de eliminar TODOS los usuarios? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        if [[ -s "$USUARIOS_FILE" ]]; then
                            while IFS=: read -r usuario _; do
                                userdel -r "$usuario" 2>/dev/null
                            done < "$USUARIOS_FILE"
                            > "$USUARIOS_FILE"
                            > "$LOCKED_USERS_FILE"
                            echo -e "\e[1;96mTodos los usuarios han sido eliminados.\e[0m"
                        else
                            echo -e "\e[1;31mNo hay usuarios para eliminar.\e[0m"
                        fi
                    else
                        echo -e "\e[1;31mEliminación cancelada.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    ;;
                3)
                    continue
                    ;;
                *)
                    echo -e "\e[1;31mOpción no válida.\e[0m"
                    read -p "Presiona enter para continuar..."
                    ;;
            esac
            ;;
        5)
            echo -e "\e[1;33mSaliendo del panel...\e[0m"
            exit 0
            ;;
        6)
            clear
            echo -e "\e[1;36m╔══════════════════════════════════════════════╗\e[0m"
            echo -e "\e[1;33m     ⚡ CONFIGURACIÓN DE PUERTOS PRO ⚡     \e[0m"
            echo -e "\e[1;36m╚══════════════════════════════════════════════╝\e[0m"
            echo -e "\e[1;35m⚡Potencia tu VPS con estilo 🌐\e[0m"
            echo -e "\e[1;36m----------------------------------------------\e[0m"
            echo -e "\e[1;96m[1] ➮ Configurar Dropbear (Puerto 444)\e[0m"
            echo -e "\e[1;33m      Instala Dropbear para conexiones SSH seguras.\e[0m"
            echo -e "\e[1;96m[2] ➮ Iniciar Proxy WS/Directo\e[0m"
            echo -e "\e[1;33m      Configura el proxy para redirigir al puerto Dropbear.\e[0m"
            echo -e "\e[1;96m[3] ➮ Verificar Estado de Puertos\e[0m"
            echo -e "\e[1;33m      Revisa si Dropbear y el proxy están activos.\e[0m"
            echo -e "\e[1;96m[4] ➮ Detener Proxy WS/Directo\e[0m"
            echo -e "\e[1;33m      Para el proxy si está corriendo.\e[0m"
            echo -e "\e[1;96m[5] ➮ Editar Configuración de Puertos\e[0m"
            echo -e "\e[1;33m      Modifica los puertos de escucha del proxy.\e[0m"
            echo -e "\e[1;31m[0] ➮ Volver al Menú Principal\e[0m"
            echo -e "\e[1;36m----------------------------------------------\e[0m"
            echo -e -n "\e[1;35m🎯 Elige tu opción: \e[0m"
            read option

            case $option in
                1)
                    if ! dpkg -s dropbear &>/dev/null; then
                        echo -e "\n\e[1;34m🔧 Instalando Dropbear...\e[0m"
                        apt install dropbear -y >/dev/null 2>&1
                        if dpkg -s dropbear &>/dev/null; then
                            echo -e "\e[1;96m[✓] Dropbear instalado correctamente.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error al instalar Dropbear.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue
                        fi
                    fi
                    echo -e "\n\e[1;34m🔧 Configurando Dropbear en puerto 444...\e[0m"
                    echo "/bin/false" >> /etc/shells 2>/dev/null
                    echo "/usr/sbin/nologin" >> /etc/shells 2>/dev/null
                    sed -i 's/^NO_START=1/NO_START=0/' /etc/default/dropbear 2>/dev/null
                    sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=444/' /etc/default/dropbear 2>/dev/null
                    echo 'DROPBEAR_EXTRA_ARGS="-p 444"' >> /etc/default/dropbear 2>/dev/null
                    systemctl restart dropbear >/dev/null 2>&1 || service dropbear restart >/dev/null 2>&1
                    if pgrep dropbear > /dev/null && ss -tuln | grep -q ":444 "; then
                        echo -e "\e[1;96m[✓] Dropbear activado en puerto 444.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] Error: No se pudo iniciar Dropbear en el puerto 444.\e[0m"
                        journalctl -u dropbear -n 10 --no-pager
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                2)
                    if ! pgrep dropbear > /dev/null; then
                        echo -e "\n\e[1;31m[✗] Dropbear no está activo. Instálalo primero.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    echo -e "\n\e[1;34m🔧 Configurando Proxy WS/Directo...\e[0m"
                    mkdir -p /etc/mccproxy
                    if [ ! -f /etc/mccproxy/proxy.py ]; then
                        echo -e "\e[1;34m🔧 Descargando proxy.py...\e[0m"
                        wget -q -O /etc/mccproxy/proxy.py https://raw.githubusercontent.com/Mccarthey-Installer/Mccarthey-Installer/main/etc/mccproxy/proxy.py
                        if [ $? -ne 0 ] || [ ! -s /etc/mccproxy/proxy.py ]; then
                            echo -e "\e[1;31m[✗] Error al descargar proxy.py. Verifica tu conexión o la URL.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue
                        fi
                        chmod +x /etc/mccproxy/proxy.py
                        echo -e "\e[1;96m[✓] proxy.py descargado correctamente.\e[0m"
                    fi
                    if ! dpkg -s screen &>/dev/null; then
                        apt install screen -y >/dev/null 2>&1
                        if dpkg -s screen &>/dev/null; then
                            echo -e "\e[1;96m[✓] Screen instalado correctamente.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error al instalar screen.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue
                        fi
                    fi
                    echo -e "\e[1;33m⚙️ Configura tu Proxy WS/Directo:\e[0m"
                    read -p "Puertos de escucha (ejemplo: 8080,443, separar con coma o espacio): " proxy_ports
                    if [[ -z "$proxy_ports" ]]; then
                        echo -e "\e[1;31m[✗] Debes especificar al menos un puerto.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    echo "$proxy_ports" | tr ',' ' ' > /etc/mccproxy_ports
                    for port in $(echo "$proxy_ports" | tr ',' ' '); do
                        if ss -tuln | grep -q ":$port "; then
                            echo -e "\e[1;31m[✗] El puerto $port ya está en uso.\e[0m"
                            read -p "Presiona enter para continuar..."
                            continue 2
                        fi
                    done
                    echo -e "\n\e[1;34m🔧 Iniciando Proxy en puertos $proxy_ports\e[0m"
                    screen -dmS proxy python3 /etc/mccproxy/proxy.py
                    sleep 2
                    if screen -list | grep -q "proxy"; then
                        echo -e "\e[1;96m[✓] Proxy WS/Directo activo en puertos $proxy_ports\e[0m"
                    else
                        echo -e "\e[1;31m[✗] Error: No se pudo iniciar el Proxy.\e[0m"
                        read -p "Presiona enter para continuar..."
                        continue
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                3)
                    echo -e "\n\e[1;34m🔍 Verificando estado de puertos...\e[0m"
                    echo -e "\e[1;36m----------------------------------------------\e[0m"
                    echo -e "\e[1;33m🌐 Estado de Dropbear (Puerto 444):\e[0m"
                    if pgrep dropbear > /dev/null && ss -tuln | grep -q ":444 "; then
                        echo -e "\e[1;96m[✓] Activo y escuchando en puerto 444.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] No activo en puerto 444.\e[0m"
                    fi
                    echo -e "\e[1;33m🌐 Estado de Proxy WS/Directo:\e[0m"
                    proxy_ports=$(cat /etc/mccproxy_ports 2>/dev/null || echo "8080")
                    for port in $proxy_ports; do
                        if ss -tuln | grep -q ":$port "; then
                            echo -e "\e[1;96m[✓] Activo y escuchando en puerto $port.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] No activo en puerto $port.\e[0m"
                        fi
                    done
                    echo -e "\e[1;36m----------------------------------------------\e[0m"
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                4)
                    echo -e "\n\e[1;34m🔧 Deteniendo Proxy WS/Directo...\e[0m"
                    if screen -list | grep -q "proxy"; then
                        screen -X -S proxy quit &>/dev/null
                        echo -e "\e[1;96m[✓] Proxy detenido correctamente.\e[0m"
                    else
                        echo -e "\e[1;31m[✗] No hay proxy corriendo.\e[0m"
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                5)
                    echo -e "\n\e[1;34m🔧 Editando configuración de puertos...\e[0m"
                    echo -e "\e[1;33m⚙️ Puertos de escucha actuales: $(cat /etc/mccproxy_ports 2>/dev/null || echo '8080')\e[0m"
                    read -p "Nuevos puertos de escucha (ejemplo: 8080,443, separar con coma o espacio): " new_proxy_ports
                    if [[ -n "$new_proxy_ports" ]]; then
                        echo "$new_proxy_ports" | tr ',' ' ' > /etc/mccproxy_ports
                        echo -e "\e[1;96m[✓] Puertos de escucha actualizados: $new_proxy_ports\e[0m"
                    fi
                    echo -e "\n\e[1;33m¿Deseas reiniciar el proxy con la nueva configuración? (s/n)\e[0m"
                    read -p "Confirma: " confirm
                    if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                        if screen -list | grep -q "proxy"; then
                            screen -X -S proxy quit &>/dev/null
                        fi
                        for port in $(cat /etc/mccproxy_ports); do
                            if ss -tuln | grep -q ":$port "; then
                                echo -e "\e[1;31m[✗] El puerto $port ya está en uso.\e[0m"
                                read -p "Presiona enter para continuar..."
                                continue 2
                            fi
                        done
                        screen -dmS proxy python3 /etc/mccproxy/proxy.py
                        sleep 2
                        if screen -list | grep -q "proxy"; then
                            echo -e "\e[1;96m[✓] Proxy reiniciado con nueva configuración.\e[0m"
                        else
                            echo -e "\e[1;31m[✗] Error: No se pudo reiniciar el Proxy.\e[0m"
                        fi
                    fi
                    read -p "Presiona enter para continuar..."
                    continue
                    ;;
                0)
                    continue
                    ;;
                *)
                    echo -e "\e[1;31m[✗] Opción no válida.\e[0m"
                    read -p "Presiona enter para continuar..."
                    ;;
            esac
            ;;
        7)
            show_online_devices
            ;;
        8)
            clear
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            echo -e "          \e[1;33mMULTI ONLINES (EXCESOS)\e[0m"
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            if [[ -s "$MULTI_ONLINES_LOG" ]]; then
                echo -e "\e[1;35m$(printf '%-5s %-12s %-14s %-30s' '' 'USUARIO' 'CONEXIONES' 'FECHA - HORA')\e[0m"
                cat "$MULTI_ONLINES_LOG"
            else
                echo -e "\e[1;31mNo hay usuarios que hayan excedido su límite.\e[0m"
            fi
            echo -e "\e[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
            read -p "Presiona enter para volver al panel principal..."
            ;;
        *)
            echo -e "\e[1;31mOpción no válida.\e[0m"
            sleep 2
            ;;
    esac
done
