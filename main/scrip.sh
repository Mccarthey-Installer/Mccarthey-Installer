#!/bin/bash

# ================================
# VARIABLES Y RUTAS
# ================================
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"

# Crear directorios si no existen
mkdir -p "$(dirname "$REGISTROS")"
mkdir -p "$(dirname "$HISTORIAL")"
mkdir -p "$(dirname "$PIDFILE")"




    
function barra_sistema() {
    # Definición colores según tu estilo
    BLANCO='\033[97m'
    AZUL='\033[94m'
    MAGENTA='\033[95m'
    ROJO='\033[91m'
    AMARILLO='\033[93m'
    VERDE='\033[92m'
    NC='\033[0m'

    # Obtener información de memoria
    MEM_TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    MEM_USO=$(free -m | awk '/^Mem:/ {print $3}')
    MEM_LIBRE=$(free -m | awk '/^Mem:/ {print $4}')
    MEM_DISPONIBLE=$(free -m | awk '/^Mem:/ {print $7}')
    MEM_PORC=$(awk "BEGIN {printf \"%.2f\", ($MEM_USO/$MEM_TOTAL)*100}")

    # Función para convertir a formato humano
    human() {
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
    MEM_DISPONIBLE_H=$(human "$MEM_DISPONIBLE")

    # Obtener información del disco duro (raíz)
    # Usamos df -h para obtener valores en formato humano y asegurarnos de que coincidan con el panel
    DISCO_INFO=$(df -h / | awk '/\// {print $2, $3, $4, $5}' | tr -d '%')
    read -r DISCO_TOTAL_H DISCO_USO_H DISCO_DISPONIBLE_H DISCO_PORC <<< "$DISCO_INFO"

    # Definir color dinámico para el porcentaje de uso del disco
    if [ "${DISCO_PORC%.*}" -ge 80 ]; then
        DISCO_PORC_COLOR="${ROJO}${DISCO_PORC}%${NC}"  # Rojo si >= 80%
    elif [ "${DISCO_PORC%.*}" -ge 50 ]; then
        DISCO_PORC_COLOR="${AMARILLO}${DISCO_PORC}%${NC}"  # Amarillo si >= 50%
    else
        DISCO_PORC_COLOR="${VERDE}${DISCO_PORC}%${NC}"  # Verde si < 50%
    fi

    # Obtener uso de CPU
    CPU_PORC=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    CPU_PORC=$(awk "BEGIN {printf \"%.0f\", $CPU_PORC}")

    # Obtener frecuencia de CPU
    CPU_MHZ=$(awk -F': ' '/^cpu MHz/ {print $2; exit}' /proc/cpuinfo)
    [[ -z "$CPU_MHZ" ]] && CPU_MHZ="Desconocido"

    # Obtener IP pública
    if command -v curl &>/dev/null; then
        IP_PUBLICA=$(curl -s ifconfig.me)
    elif command -v wget &>/dev/null; then
        IP_PUBLICA=$(wget -qO- ifconfig.me)
    else
        IP_PUBLICA="No disponible"
    fi

    # Obtener fecha actual
    FECHA_ACTUAL=$(date +"%Y-%m-%d %I:%M")
    FECHA_ACTUAL_DIA=$(date +%F)

    # Inicializar variables
    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    USUARIOS_EXPIRAN=()

    if [[ -f "$REGISTROS" ]]; then
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do
            usuario=${user_data%%:*}
            if id "$usuario" &>/dev/null; then
                # Contar conexiones SSH y Dropbear
                CONEXIONES_SSH=$(ps -u "$usuario" -o comm= | grep -c "^sshd$")
                CONEXIONES_DROPBEAR=$(ps -u "$usuario" -o comm= | grep -c "^dropbear$")
                CONEXIONES=$((CONEXIONES_SSH + CONEXIONES_DROPBEAR))
                TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))
                ((TOTAL_USUARIOS++))

                # Calcular días restantes
                DIAS_RESTANTES=$(calcular_dias_restantes "$fecha_expiracion")

                # Verificar si el usuario expira hoy (0 días restantes)
                if [[ $DIAS_RESTANTES -eq 0 ]]; then
                    USUARIOS_EXPIRAN+=("${BLANCO}${usuario}${NC} ${AMARILLO}0 Días${NC}")
                fi
            fi
        done < "$REGISTROS"
    fi

    # Obtener información del sistema operativo
    if [[ -f /etc/os-release ]]; then
        SO_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    else
        SO_NAME=$(uname -o)
    fi

    # Imprimir barra de sistema
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 💾 TOTAL: ${AMARILLO}${MEM_TOTAL_H}${NC} ∘ ${BLANCO}💿 DISPONIBLE: ${AMARILLO}${MEM_DISPONIBLE_H}${NC} ∘ ${BLANCO}🔥 ${DISCO_TOTAL_H} HDD: ${AMARILLO}USO ${DISCO_PORC_COLOR}${NC}"
    echo -e "${BLANCO} 📊 U/RAM: ${AMARILLO}${MEM_PORC}%${NC} ∘ ${BLANCO}🖥️ U/CPU: ${AMARILLO}${CPU_PORC}%${NC} ∘ ${BLANCO}🔧 CPU MHz: ${AMARILLO}${CPU_MHZ}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLANCO} 🌍 IP: ${AMARILLO}${IP_PUBLICA}${NC} ∘ ${BLANCO}🕒 FECHA: ${AMARILLO}${FECHA_ACTUAL}${NC}"
    echo -e "${MAGENTA}🤴 𝐌𝐜𝐜𝐚𝐫𝐭𝐡𝐞𝐲${NC}"
    echo -e "${BLANCO}🔗 ONLINE:${AMARILLO}${TOTAL_CONEXIONES}${NC}   ${BLANCO}👥 TOTAL:${AMARILLO}${TOTAL_USUARIOS}${NC}   ${BLANCO}🖼️ SO:${AMARILLO}${SO_NAME}${NC}"
    echo -e "${AZUL}═══════════════════════════════════════════════════${NC}"

    # Mostrar usuarios que expiran hoy en una sola fila debajo del encabezado
    if [[ ${#USUARIOS_EXPIRAN[@]} -gt 0 ]]; then
        echo -e "\n${ROJO}⚠️ USUARIOS QUE EXPIRAN HOY:${NC}"
        echo -e "${USUARIOS_EXPIRAN[*]}"
    fi
}

function informacion_usuarios() {
    clear

    # Definir colores
    ROSADO='\033[38;5;211m'
    LILA='\033[38;5;183m'
    TURQUESA='\033[38;5;45m'
    NC='\033[0m'

    echo -e "${ROSADO}🌸✨  INFORMACIÓN DE CONEXIONES 💖✨ 🌸${NC}"

    # Mapa de meses para traducción
    declare -A month_map=(
        ["Jan"]="enero" ["Feb"]="febrero" ["Mar"]="marzo" ["Apr"]="abril"
        ["May"]="mayo" ["Jun"]="junio" ["Jul"]="julio" ["Aug"]="agosto"
        ["Sep"]="septiembre" ["Oct"]="octubre" ["Nov"]="noviembre" ["Dec"]="diciembre"
    )

    # Verificar si el archivo HISTORIAL existe
    if [[ ! -f "$HISTORIAL" ]]; then
        echo -e "${LILA}😿 ¡Oh no! No hay historial de conexiones aún, pequeña! 💔${NC}"
        read -p "$(echo -e ${TURQUESA}Presiona Enter para seguir, corazón... 💌${NC})"
        return 1
    fi

    # Encabezado de la tabla
    printf "${LILA}%-15s %-22s %-22s %-12s${NC}\n" "👩‍💼 Usuaria" "🌷 Conectada" "🌙 Desconectada" "⏰  Duración"
    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"

    # Obtener lista única de usuarios desde HISTORIAL
    mapfile -t USUARIOS < <(awk -F'|' '{print $1}' "$HISTORIAL" | sort -u)

    for USUARIO in "${USUARIOS[@]}"; do
        if id "$USUARIO" &>/dev/null; then
            # Obtener el último registro del usuario
            ULTIMO_REGISTRO=$(grep "^$USUARIO|" "$HISTORIAL" | tail -1)
            if [[ -n "$ULTIMO_REGISTRO" ]]; then
                IFS='|' read -r _ HORA_CONEXION HORA_DESCONEXION DURACION <<< "$ULTIMO_REGISTRO"

                # Validar formato de fechas
                if [[ "$HORA_CONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ && \
                      "$HORA_DESCONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then

                    # Formatear fechas
                    CONEXION_FMT=$(date -d "$HORA_CONEXION" +"%d/%b %I:%M %p" 2>/dev/null)
                    DESCONEXION_FMT=$(date -d "$HORA_DESCONEXION" +"%d/%b %I:%M %p" 2>/dev/null)

                    # Traducir meses a español
                    for eng in "${!month_map[@]}"; do
                        esp=${month_map[$eng]}
                        CONEXION_FMT=${CONEXION_FMT/$eng/$esp}
                        DESCONEXION_FMT=${DESCONEXION_FMT/$eng/$esp}
                    done

                    # Calcular duración
                    SEC_CON=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                    SEC_DES=$(date -d "$HORA_DESCONEXION" +%s 2>/dev/null)

                    if [[ -n "$SEC_CON" && -n "$SEC_DES" && $SEC_DES -ge $SEC_CON ]]; then
                        DURACION_SEG=$((SEC_DES - SEC_CON))
                        HORAS=$((DURACION_SEG / 3600))
                        MINUTOS=$(((DURACION_SEG % 3600) / 60))
                        SEGUNDOS=$((DURACION_SEG % 60))
                        DURACION=$(printf "%02d:%02d:%02d" $HORAS $MINUTOS $SEGUNDOS)
                    else
                        DURACION="N/A"
                    fi

                    # Mostrar fila
                    printf "${TURQUESA}%-15s %-22s %-22s %-12s${NC}\n" "$USUARIO" "$CONEXION_FMT" "$DESCONEXION_FMT" "$DURACION"
                fi
            fi
        fi
    done

    echo -e "${ROSADO}~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${NC}"
    read -p "$(echo -e ${LILA}Presiona Enter para continuar, dulce... 🌟${NC})"
}
                    
        
    
# Función para calcular la fecha de expiración
calcular_expiracion() {
    local dias=$1
    local fecha_expiracion=$(date -d "+$dias days" "+%d/%B/%Y")
    echo $fecha_expiracion
}
calcular_dias_restantes() {
    local fecha_expiracion="$1"

    local dia=$(echo "$fecha_expiracion" | cut -d'/' -f1)
    local mes=$(echo "$fecha_expiracion" | cut -d'/' -f2)
    local anio=$(echo "$fecha_expiracion" | cut -d'/' -f3)

    # Convertir mes español a número
    case $mes in
        "enero") mes_num="01" ;;
        "febrero") mes_num="02" ;;
        "marzo") mes_num="03" ;;
        "abril") mes_num="04" ;;
        "mayo") mes_num="05" ;;
        "junio") mes_num="06" ;;
        "julio") mes_num="07" ;;
        "agosto") mes_num="08" ;;
        "septiembre") mes_num="09" ;;
        "octubre") mes_num="10" ;;
        "noviembre") mes_num="11" ;;
        "diciembre") mes_num="12" ;;
        *) echo 0; return ;;
    esac

    local fecha_formateada="$anio-$mes_num-$dia"
    local fecha_actual=$(date "+%Y-%m-%d")

    local fecha_exp_epoch=$(date -d "$fecha_formateada" "+%s" 2>/dev/null)
    local fecha_act_epoch=$(date -d "$fecha_actual" "+%s")

    if [[ -z "$fecha_exp_epoch" ]]; then
        echo 0
        return
    fi

    local diff_segundos=$((fecha_exp_epoch - fecha_act_epoch))
    local dias_restantes=$((diff_segundos / 86400))

    if [ $dias_restantes -lt 0 ]; then
        dias_restantes=0
    fi

    echo $dias_restantes
}
# Función para crear usuario
function crear_usuario() {
    clear
    echo -e "${VIOLETA}===== 🤪 CREAR USUARIO SSH =====${NC}"
    read -p "$(echo -e ${AZUL}👤 Nombre del usuario: ${NC})" usuario
    read -p "$(echo -e ${AZUL}🔑 Contraseña: ${NC})" clave
    read -p "$(echo -e ${AZUL}📅 Días de validez: ${NC})" dias
    read -p "$(echo -e ${AZUL}📱 ¿Cuántos móviles? ${NC})" moviles

    # Validar entradas
    if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
        echo -e "${ROJO}❌ Todos los campos son obligatorios.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${ROJO}❌ Días y móviles deben ser números.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Verificar si el usuario ya existe en el sistema
    if id "$usuario" >/dev/null 2>&1; then
        echo -e "${ROJO}❌ El usuario $usuario ya existe en el sistema.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Crear usuario en el sistema Linux
    if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
        echo -e "${ROJO}❌ Error al crear el usuario en el sistema.${NC}"
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Establecer la contraseña
    if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
        echo -e "${ROJO}❌ Error al establecer la contraseña.${NC}"
        userdel "$usuario" 2>/dev/null
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Configurar fecha de expiración en el sistema (a las 00:00 del día siguiente al último día)
    fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo -e "${ROJO}❌ Error al establecer la fecha de expiración.${NC}"
        userdel "$usuario" 2>/dev/null
        read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
        return
    fi

    # Obtener fecha actual y de expiración para registros
    fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    # Guardar en archivo de registros
    echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

    # Guardar en historial
    echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL

    # Mostrar confirmación
    echo -e "${VERDE}✅ Usuario creado correctamente:${NC}"
    echo -e "${AZUL}👤 Usuario: ${AMARILLO}$usuario${NC}"
    echo -e "${AZUL}🔑 Clave: ${AMARILLO}$clave${NC}"
    echo -e "${AZUL}📅 Expira: ${AMARILLO}$fecha_expiracion${NC}"
    echo -e "${AZUL}📱 Límite móviles: ${AMARILLO}$moviles${NC}"
    echo -e "${AZUL}📅 Creado: ${AMARILLO}$fecha_creacion${NC}"
    echo -e "${VIOLETA}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo -e "${AMARILLO}👤 Usuario    📅 Expira        ⏳ Días      📱 Móviles    📅 Creado${NC}"
    echo -e "${CIAN}---------------------------------------------------------------${NC}"
    printf "${VERDE}%-12s %-18s %-12s %-12s %s${NC}\n" "$usuario:$clave" "$fecha_expiracion" "$dias días" "$moviles" "$fecha_creacion"
    echo -e "${CIAN}===============================================================${NC}"
    read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
}

function ver_registros() {
    clear
    echo -e "${VIOLETA}===== 🌸 REGISTROS =====${NC}"
    echo -e "${AMARILLO}Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳  Días   📲 Móviles${NC}"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros disponibles.${NC}"
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "${VERDE}%-2s ${VERDE}%-11s ${AZUL}%-10s ${AMARILLO}%-16s ${VERDE}%-8s ${AMARILLO}%-8s${NC}\n" \
                "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "$(echo -e ${CIAN}Presiona Enter para continuar...${NC})"
}

function mini_registro() {
    clear
    echo -e "${VIOLETA}==== 📋 MINI REGISTRO ====${NC}"
    echo -e "${AMARILLO}👤 Nombre  🔑 Contraseña   ⏳ Días   📱 Móviles${NC}"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo -e "${ROJO}No hay registros disponibles.${NC}"
    else
        count=0
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            printf "${VERDE}%-12s ${AZUL}%-16s ${AMARILLO}%-10s ${AMARILLO}%-10s${NC}\n" \
                "$usuario" "$clave" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
        echo -e "${CIAN}===========================================${NC}"
        echo -e "${AMARILLO}TOTAL: ${VERDE}$count usuarios${NC}"
    fi
    echo -e "${CIAN}Presiona Enter para continuar... ✨${NC}"
    read
}

# ================================
# FUNCIÓN: ACTIVAR/DESACTIVAR LIMITADOR
# ================================
activar_desactivar_limitador() {
    clear
    AZUL_SUAVE='\033[38;5;45m'
    VERDE='\033[38;5;42m'
    ROJO='\033[38;5;196m'
    AMARILLO='\033[38;5;226m'
    NC='\033[0m'
    LIMITADOR_PIDFILE="/Abigail/limitador.pid"
    LIMITADOR_LOG="/var/log/limitador_conexiones.log"
    LIMITADOR_STATUS="/tmp/limitador_status"

    echo -e "${AZUL_SUAVE}===== ⚙️  ACTIVAR/DESACTIVAR LIMITADOR DE CONEXIONES =====${NC}"
    
    # Verificar estado actual del limitador
    if [[ -f "$LIMITADOR_PIDFILE" ]] && ps -p "$(cat "$LIMITADOR_PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
        ESTADO="🟢 Activado"
        INTERVALO_ACTUAL=$(cat "$LIMITADOR_STATUS" 2>/dev/null || echo "1")
    else
        ESTADO="🔴 Desactivado"
        INTERVALO_ACTUAL="N/A"
    fi

    echo -e "${AMARILLO}Estado actual: ${ESTADO}${NC}"
    echo -e "${AMARILLO}Intervalo actual: ${INTERVALO_ACTUAL} segundo(s)${NC}"
    echo -e "${AZUL_SUAVE}----------------------------------------------------------${NC}"

    # Preguntar al usuario
    echo -ne "${VERDE}¿Desea activar/desactivar el limitador? (s/n): ${NC}"
    read respuesta

    if [[ "$respuesta" =~ ^[sS]$ ]]; then
        if [[ "$ESTADO" == "🟢 Activado" ]]; then
            # Desactivar limitador
            kill -9 "$(cat "$LIMITADOR_PIDFILE" 2>/dev/null)" 2>/dev/null
            rm -f "$LIMITADOR_PIDFILE" "$LIMITADOR_STATUS"
            echo -e "${VERDE}✅ Limitador desactivado exitosamente.${NC}"
            echo "$(date '+%Y-%m-%d %H:%M:%S'): Limitador desactivado." >> "$LIMITADOR_LOG"
        else
            # Activar limitador
            echo -ne "${VERDE}Ingrese el intervalo de verificación en segundos (1-60): ${NC}"
            read intervalo
            if [[ "$intervalo" =~ ^[0-9]+$ ]] && [[ "$intervalo" -ge 1 && "$intervalo" -le 60 ]]; then
                echo "$intervalo" > "$LIMITADOR_STATUS"
                nohup bash "$0" limitador >/dev/null 2>&1 &
                echo $! > "$LIMITADOR_PIDFILE"
                echo -e "${VERDE}✅ Limitador activado con intervalo de $intervalo segundo(s).${NC}"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): Limitador activado con intervalo de $intervalo segundos." >> "$LIMITADOR_LOG"
            else
                echo -e "${ROJO}❌ Intervalo inválido. Debe ser un número entre 1 y 60.${NC}"
            fi
        fi
    else
        echo -e "${AMARILLO}⚠️ Operación cancelada.${NC}"
    fi

    echo -ne "${AZUL_SUAVE}Presiona Enter para continuar...${NC}"
    read
}
# ================================
# MODO LIMITADOR
# ================================
if [[ "$1" == "limitador" ]]; then
    LIMITADOR_LOG="/var/log/limitador_conexiones.log"
    INTERVALO=$(cat "/tmp/limitador_status" 2>/dev/null || echo "1")

    while true; do
        if [[ -f "$REGISTROS" ]]; then
            while IFS=' ' read -r user_data _ _ moviles _; do
                usuario=${user_data%%:*}
                if id "$usuario" &>/dev/null; then
                    # Obtener PIDs ordenados por start_time ascendente (más antiguo primero)
                    pids=($(ps -u "$usuario" --sort=start_time -o pid,comm | grep -E '^[ ]*[0-9]+ (sshd|dropbear)$' | awk '{print $1}'))
                    conexiones=${#pids[@]}
                    if [[ $conexiones -gt $moviles ]]; then
                        num_extras=$((conexiones - moviles))
                        for ((i=0; i<num_extras; i++)); do
                            pid=${pids[$((conexiones - 1 - i))]}
                            kill -9 "$pid" 2>/dev/null
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): Conexión extra de $usuario (PID: $pid) terminada. Límite: $moviles, Conexiones: $conexiones" >> "$LIMITADOR_LOG"
                        done
                    fi
                fi
            done < "$REGISTROS"
        fi
        sleep "$INTERVALO"
    done
fi

# Función para crear múltiples usuarios
crear_multiples_usuarios() {
    clear
    echo "===== 🆕 CREAR MÚLTIPLES USUARIOS SSH ====="
    echo "📝 Formato: nombre contraseña días móviles (separados por espacios, una línea por usuario)"
    echo "📋 Ejemplo: lucy 123 5 4"
    echo "✅ Presiona Enter dos veces para confirmar."

    # Array para almacenar las entradas de usuarios
    declare -a usuarios_input
    while true; do
        read -r linea
        # Si la línea está vacía y la anterior también, salir del bucle
        if [[ -z "$linea" ]]; then
            read -r linea_siguiente
            if [[ -z "$linea_siguiente" ]]; then
                break
            else
                usuarios_input+=("$linea" "$linea_siguiente")
                continue
            fi
        fi
        usuarios_input+=("$linea")
    done

    # Verificar si se ingresaron usuarios
    if [ ${#usuarios_input[@]} -eq 0 ]; then
        echo "❌ No se ingresaron usuarios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar y validar entradas
    declare -a usuarios_validos
    declare -a errores
    for linea in "${usuarios_input[@]}"; do
        # Separar los campos
        read -r usuario clave dias moviles <<< "$linea"

        # Validar que todos los campos estén presentes
        if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
            errores+=("Línea '$linea': Todos los campos son obligatorios.")
            continue
        fi

        # Validar que días y móviles sean números
        if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
            errores+=("Línea '$linea': Días y móviles deben ser números.")
            continue
        fi

        # Verificar si el usuario ya existe en el sistema
        if id "$usuario" >/dev/null 2>&1; then
            errores+=("Línea '$linea': El usuario $usuario ya existe en el sistema.")
            continue
        fi

        # Almacenar usuario válido
        usuarios_validos+=("$usuario:$clave:$dias:$moviles")
    done

    # Mostrar errores si los hay
    if [ ${#errores[@]} -gt 0 ]; then
        echo "❌ Errores encontrados:"
        for error in "${errores[@]}"; do
            echo "$error"
        done
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar resumen de usuarios a crear
    echo "===== 📋 USUARIOS A CREAR ====="
    echo "👤 Usuario    🔑 Clave      ⏳ Días       📱 Móviles"
    echo "---------------------------------------------------------------"
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"
        printf "%-12s %-12s %-12s %-12s\n" "$usuario" "$clave" "$dias" "$moviles"
    done
    echo "==============================================================="

    # Confirmar creación
    read -p "✅ ¿Confirmar creación de estos usuarios? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Creación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuarios y registrar
    count=0
    for usuario_data in "${usuarios_validos[@]}"; do
        IFS=':' read -r usuario clave dias moviles <<< "$usuario_data"

        # Crear usuario en el sistema Linux
        if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
            echo "❌ Error al crear el usuario $usuario en el sistema."
            continue
        fi

        # Establecer la contraseña
        if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
            echo "❌ Error al establecer la contraseña para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Configurar fecha de expiración en el sistema
        fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
        if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
            echo "❌ Error al establecer la fecha de expiración para $usuario."
            userdel "$usuario" 2>/dev/null
            continue
        fi

        # Obtener fecha actual y de expiración para registros
        fecha_creacion=$(date "+%Y-%m-%d %H:%M:%S")
        fecha_expiracion=$(calcular_expiracion $dias)

        # Guardar en archivo de registros
        echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> $REGISTROS

        # Guardar en historial
        echo "Usuario creado: $usuario, Expira: $fecha_expiracion, Móviles: $moviles, Creado: $fecha_creacion" >> $HISTORIAL

        ((count++))
    done

    # Mostrar resumen de creación
    echo "===== 📊 RESUMEN DE CREACIÓN ====="
    echo "✅ Usuarios creados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
}


# Función para eliminar múltiples usuarios
eliminar_multiples_usuarios() {
    clear
    echo "===== 💣 ELIMINAR USUARIO: NIVEL DIABLO - SATÁN ROOT 🔥 ====="
    echo "Nº      👤 Usuario"
    echo "--------------------------"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Cargar usuarios en un array para fácil acceso por número
    declare -a usuarios
    count=1
    while IFS=' ' read -r user_data _; do
        usuario=${user_data%%:*}
        usuarios[$count]="$usuario"
        printf "%-7s %-20s\n" "$count" "$usuario"
        ((count++))
    done < $REGISTROS

    read -p "🗑️ Ingrese los números o nombres de usuarios a eliminar (separados por espacios) (0 para cancelar): " input

    if [[ "$input" == "0" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Procesar input: puede ser números o nombres
    declare -a usuarios_a_eliminar
    for item in $input; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Es un número
            if [[ $item -ge 1 && $item -lt $count ]]; then
                usuarios_a_eliminar+=("${usuarios[$item]}")
            else
                echo "❌ Número inválido: $item"
            fi
        else
            # Es un nombre, verificar si existe
            if grep -q "^$item:" $REGISTROS; then
                usuarios_a_eliminar+=("$item")
            else
                echo "❌ Usuario no encontrado: $item"
            fi
        fi
    done

    # Eliminar duplicados si los hay
    usuarios_a_eliminar=($(echo "${usuarios_a_eliminar[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

    if [ ${#usuarios_a_eliminar[@]} -eq 0 ]; then
        echo "❌ No se seleccionaron usuarios válidos."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Confirmar eliminación
    echo "===== 📋 USUARIOS A ELIMINAR ====="
    for usuario in "${usuarios_a_eliminar[@]}"; do
        echo "👤 $usuario"
    done
    read -p "✅ ¿Confirmar eliminación? (s/n): " confirmacion
    if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
        echo "❌ Eliminación cancelada."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Eliminar usuarios
    count=0
    fecha_eliminacion=$(date "+%Y-%m-%d %H:%M:%S")
    for usuario in "${usuarios_a_eliminar[@]}"; do
        # Terminar sesiones activas si existen (usando loginctl si está disponible)
        if command -v loginctl >/dev/null 2>&1; then
            loginctl terminate-user "$usuario" 2>/dev/null
        else
            # Alternativa: matar procesos del usuario
            pkill -9 -u "$usuario" 2>/dev/null
        fi

        # Eliminar usuario del sistema
        if userdel "$usuario" 2>/dev/null; then
            # Eliminar del registro
            sed -i "/^$usuario:/d" $REGISTROS

            # Registrar en historial
            echo "Usuario eliminado: $usuario, Fecha: $fecha_eliminacion" >> $HISTORIAL

            ((count++))
        else
            echo "❌ Error al eliminar el usuario $usuario del sistema."
        fi
    done

    # Mostrar resumen
    echo "===== 📊 RESUMEN DE ELIMINACIÓN ====="
    echo "✅ Usuarios eliminados exitosamente: $count"
    echo "Presiona Enter para continuar... ✨"
    read
}



        # ================================
#  FUNCIÓN: MONITOREAR CONEXIONES
# ================================
monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=1

    while true; do
        # Usuarios conectados ahora mismo por SSH o Dropbear
        usuarios_ps=$(ps -o user= -C sshd -C dropbear | sort -u)

        for usuario in $usuarios_ps; do
            [[ -z "$usuario" ]] && continue
            tmp_status="/tmp/status_${usuario}.tmp"

            # ¿Cuántas conexiones tiene activas?
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                # Si nunca se ha creado el reloj, créalo ahora
                if [[ ! -f "$tmp_status" ]]; then
                    date +%s > "$tmp_status"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                else
                    # Reparar si está corrupto
                    contenido=$(cat "$tmp_status")
                    [[ ! "$contenido" =~ ^[0-9]+$ ]] && date +%s > "$tmp_status"
                fi
            fi
        done

        # Ahora, ver quién estaba conectado y ya NO está, para cerrarles el tiempo
        for f in /tmp/status_*.tmp; do
            [[ ! -f "$f" ]] && continue
            usuario=$(basename "$f" .tmp | cut -d_ -f2)
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))
            if [[ $conexiones -eq 0 ]]; then
                hora_ini=$(date -d @"$(cat "$f")" "+%Y-%m-%d %H:%M:%S")
                hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                rm -f "$f"
                echo "$usuario|$hora_ini|$hora_fin" >> "$HISTORIAL"
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Inicio: $hora_ini Fin: $hora_fin" >> "$LOG"
            fi
        done

        sleep "$INTERVALO"
    done
}



# ================================
#  MODO MONITOREO DIRECTO
# ================================
if [[ "$1" == "mon" ]]; then
    monitorear_conexiones
    exit 0
fi

# ================================
#  ARRANQUE AUTOMÁTICO DEL MONITOR
# ================================
if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE"
    nohup bash "$0" mon >/dev/null 2>&1 &
    echo $! > "$PIDFILE"
fi

# ================================

# ================================
# ARRANQUE AUTOMÁTICO DEL LIMITADOR
# ================================
if [[ ! -f "$LIMITADOR_PIDFILE" ]] || ! ps -p "$(cat "$LIMITADOR_PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$LIMITADOR_PIDFILE"
    if [[ -f "/tmp/limitador_status" ]]; then
        nohup bash "$0" limitador >/dev/null 2>&1 &
        echo $! > "$LIMITADOR_PIDFILE"
    fi
fi

function verificar_online() {
    clear

    # Definir colores exactos
    AZUL_SUAVE='\033[38;5;45m'
    SOFT_PINK='\033[38;5;211m'
    PASTEL_BLUE='\033[38;5;153m'
    LILAC='\033[38;5;183m'
    SOFT_CORAL='\033[38;5;217m'
    HOT_PINK='\033[38;5;198m'
    PASTEL_PURPLE='\033[38;5;189m'
    MINT_GREEN='\033[38;5;159m'
    VERDE='\033[38;5;42m'
    VIOLETA='\033[38;5;183m'
    ROJO='\033[38;5;196m'
    NC='\033[0m'

    echo -e "${AZUL_SUAVE}===== ✅   USUARIOS ONLINE =====${NC}"
    printf "${AMARILLO}%-14s ${AMARILLO}%-14s ${AMARILLO}%-10s ${AMARILLO}%-25s${NC}\n" \
        "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo -e "${LILAC}-----------------------------------------------------------------${NC}"

    total_online=0
    total_usuarios=0
    inactivos=0

    if [[ ! -f "$REGISTROS" ]]; then
        echo -e "${HOT_PINK}❌ No hay registros.${NC}"
        read -p "$(echo -e ${PASTEL_PURPLE}Presiona Enter para continuar... ✨${NC})"
        return
    fi

    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}

        if ! id "$usuario" &>/dev/null; then
            continue
        fi

        (( total_usuarios++ ))
        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -cE "^(sshd|dropbear)$") ))

        estado="📵 0"
        detalle="😴 Nunca conectado"
        mov_txt="✅ $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"
        COLOR_ESTADO="${ROJO}"
        COLOR_DETALLE="${VIOLETA}"

        if [[ $conexiones -gt 0 ]]; then
            estado="📱 $conexiones"
            COLOR_ESTADO="${MINT_GREEN}"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                contenido=$(cat "$tmp_status")
                if [[ "$contenido" =~ ^[0-9]+$ ]]; then
                    start_s=$((10#$contenido))
                else
                    start_s=$(date +%s)
                    echo $start_s > "$tmp_status"
                fi

                now_s=$(date +%s)
                elapsed=$(( now_s - start_s ))
                h=$(( elapsed / 3600 ))
                m=$(( (elapsed % 3600) / 60 ))
                s=$(( elapsed % 60 ))
                detalle=$(printf "⏰ %02d:%02d:%02d" "$h" "$m" "$s")
                COLOR_DETALLE="${VERDE}"
            fi
        else
            rm -f "$tmp_status"
            ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
            if [[ -n "$ult" ]]; then
                ult_fmt=$(date -d "$ult" +"%d de %B %H:%M")
                detalle="📅 Última: $ult_fmt"
                COLOR_DETALLE="${ROJO}"
            else
                detalle="😴 Nunca conectado"
                COLOR_DETALLE="${VIOLETA}"
            fi
            (( inactivos++ ))
        fi

        printf "${VERDE}%-14s ${COLOR_ESTADO}%-14s ${VERDE}%-10s ${COLOR_DETALLE}%-25s${NC}\n" \
            "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo -e "${LILAC}-----------------------------------------------------------------${NC}"
    echo -e "${CIAN}Total de Online: ${AMARILLO}${total_online}${NC}  ${CIAN}Total usuarios: ${AMARILLO}${total_usuarios}${NC}  ${CIAN}Inactivos: ${AMARILLO}${inactivos}${NC}"
    echo -e "${HOT_PINK}================================================${NC}"
    read -p "$(echo -e ${VIOLETA}Presiona Enter para continuar... ✨${NC})"
}


bloquear_desbloquear_usuario() {
    clear
    AZUL_SUAVE='\033[38;5;45m'
    LILAC='\033[38;5;183m'
    VERDE='\033[38;5;42m'
    ROJO='\033[38;5;196m'
    AMARILLO='\033[38;5;226m'
    NC='\033[0m'

    printf "${AZUL_SUAVE}==== 🔒 BLOQUEAR/DESBLOQUEAR USUARIO ====${NC}\n"
    printf "${LILAC}===== 📋 USUARIOS REGISTRADOS =====${NC}\n"
    printf "${AMARILLO}%-4s %-15s %-15s %-22s %-25s${NC}\n" "Nº" "👤 Usuario" "🔑 Clave" "📅 Expira" "✅ Estado"
    printf "${LILAC}--------------------------------------------------------------------------${NC}\n"

    usuarios=()
    index=1
    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        clave=${userpass#*:}
        estado="desbloqueado"
        COLOR_ESTADO="${VERDE}"
        bloqueo_file="/tmp/bloqueo_${usuario}.lock"

        if [[ -f "$bloqueo_file" ]]; then
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -lt $bloqueo_hasta ]]; then
                estado="bloqueado (hasta $(date -d @$bloqueo_hasta '+%I:%M%p'))"
                COLOR_ESTADO="${ROJO}"
            else
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                estado="desbloqueado"
                COLOR_ESTADO="${VERDE}"
            fi
        fi

        printf "%-4s ${VERDE}%-15s ${VERDE}%-15s ${VERDE}%-22s ${COLOR_ESTADO}%-25s${NC}\n" \
            "$index" "$usuario" "$clave" "$fecha_exp" "$estado"

        usuarios[$index]="$usuario"
        ((index++))
    done < "$REGISTROS"

    printf "${LILAC}==========================================================================${NC}\n"
    read -p "👤 Digite el número o el nombre del usuario: " input

    if [[ "$input" =~ ^[0-9]+$ ]] && [[ -n "${usuarios[$input]}" ]]; then
        usuario="${usuarios[$input]}"
    else
        usuario="$input"
    fi

    if ! grep -q "^${usuario}:" "$REGISTROS"; then
        printf "${ROJO}❌ Usuario '$usuario' no encontrado.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    bloqueo_file="/tmp/bloqueo_${usuario}.lock"
    if [[ -f "$bloqueo_file" ]] && [[ $(date +%s) -lt $(cat "$bloqueo_file") ]]; then
        printf "𒯢 El usuario '$usuario' está ${ROJO}BLOQUEADO${NC} hasta $(date -d @$(cat "$bloqueo_file") '+%I:%M%p').\n"
        read -p "✅ Desea desbloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            rm -f "$bloqueo_file"
            usermod -U "$usuario" 2>/dev/null
            loginctl terminate-user "$usuario" 2>/dev/null
            pkill -9 -u "$usuario" 2>/dev/null
            killall -u "$usuario" -9 2>/dev/null
            printf "${VERDE}🔓 Usuario '$usuario' desbloqueado exitosamente.${NC}\n"
        else
            printf "${AMARILLO}⚠️ Operación cancelada.${NC}\n"
        fi
        read -p "Presiona Enter para continuar..."
        return
    else
        printf "𒯢 El usuario '$usuario' está ${VERDE}DESBLOQUEADO${NC}.\n"
        read -p "✅ Desea bloquear al usuario '$usuario'? (s/n) " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            read -p "Ponga en minutos el tiempo que el usuario estaría bloqueado y confirmar con Enter: " minutos
            if [[ "$minutos" =~ ^[0-9]+$ ]] && [[ $minutos -gt 0 ]]; then
                bloqueo_hasta=$(( $(date +%s) + minutos * 60 ))
                echo "$bloqueo_hasta" > "$bloqueo_file"
                usermod -L "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                printf "${VERDE}🔒 Usuario '$usuario' bloqueado exitosamente y sesiones SSH terminadas. ✅${NC}\n"
                printf "Desbloqueado automáticamente hasta las $(date -d @$bloqueo_hasta '+%I:%M%p')\n"
            else
                printf "${ROJO}❌ Tiempo inválido. Debe ser un número mayor a 0.${NC}\n"
            fi
        else
            printf "${AMARILLO}⚠️ Operación cancelada.${NC}\n"
        fi
        read -p "Presiona Enter para continuar..."
    fi
}

monitorear_bloqueos() {
    LOG="/var/log/monitoreo_bloqueos.log"
    INTERVALO=10 # Verificar cada 10 segundos

    while true; do
        for bloqueo_file in /tmp/bloqueo_*.lock; do
            [[ ! -f "$bloqueo_file" ]] && continue
            usuario=$(basename "$bloqueo_file" .lock | cut -d_ -f2)
            bloqueo_hasta=$(cat "$bloqueo_file")
            if [[ $(date +%s) -ge $bloqueo_hasta ]]; then
                rm -f "$bloqueo_file"
                usermod -U "$usuario" 2>/dev/null
                loginctl terminate-user "$usuario" 2>/dev/null
                pkill -9 -u "$usuario" 2>/dev/null
                killall -u "$usuario" -9 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desbloqueado automáticamente." >> "$LOG"
            fi
        done
        sleep "$INTERVALO"
    done
}

# ================================
#  ARRANQUE AUTOMÁTICO DEL MONITOR DE BLOQUEOS
# ================================
if [[ ! -f "$PIDFILE.bloqueos" ]] || ! ps -p "$(cat "$PIDFILE.bloqueos" 2>/dev/null)" >/dev/null 2>&1; then
    rm -f "$PIDFILE.bloqueos"
    nohup bash "$0" mon_bloqueos >/dev/null 2>&1 &
    echo $! > "$PIDFILE.bloqueos"
fi

# ================================
#  MODO MONITOREO DE BLOQUEOS
# ================================
if [[ "$1" == "mon_bloqueos" ]]; then
    monitorear_bloqueos
    exit 0
fi
# Colores y emojis
VIOLETA='\033[38;5;141m'
VERDE='\033[38;5;42m'
AMARILLO='\033[38;5;220m'
AZUL='\033[38;5;39m'
ROJO='\033[1;31m'
CIAN='\033[38;5;51m'
FUCHSIA='\033[38;2;255;0;255m'
AMARILLO_SUAVE='\033[38;2;255;204;0m'
ROSA='\033[38;2;255;105;180m'
ROSA_CLARO='\033[1;95m'
NC='\033[0m'

# Menú principal
if [[ -t 0 ]]; then
    while true; do
        clear
        barra_sistema
        echo
        echo -e "${VIOLETA}======📱PANEL DE USUARIOS VPN/SSH ======${NC}"
        echo -e "${AMARILLO_SUAVE}1. 🆕 Crear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}2. 📋 Ver registros${NC}"
        echo -e "${AMARILLO_SUAVE}3. 🗑️ Eliminar usuario${NC}"
        echo -e "${AMARILLO_SUAVE}4. 📊 Información${NC}"
        echo -e "${AMARILLO_SUAVE}5. 🟢 Verificar usuarios online${NC}"
        echo -e "${AMARILLO_SUAVE}6. 🔒 Bloquear/Desbloquear usuario${NC}"
        echo -e "${AMARILLO_SUAVE}7. 🆕 Crear múltiples usuarios${NC}"
        echo -e "${AMARILLO_SUAVE}8. 📋 Mini registro${NC}"
        echo -e "${AMARILLO_SUAVE}9. ⚙️ Activar/Desactivar limitador${NC}"
        echo -e "${AMARILLO_SUAVE}10. 🎨 Configurar banner SSH${NC}"
        echo -e "${AMARILLO_SUAVE}0. 🚪 Salir${NC}"
        PROMPT=$(echo -e "${ROSA}➡️ Selecciona una opción: ${NC}")
        read -p "$PROMPT" OPCION
        case $OPCION in
            1) crear_usuario ;;
            2) ver_registros ;;
            3) eliminar_multiples_usuarios ;;
            4) informacion_usuarios ;;
            5) verificar_online ;;
            6) bloquear_desbloquear_usuario ;;
            7) crear_multiples_usuarios ;;
            8) mini_registro ;;
            9) activar_desactivar_limitador ;;  # Añade esta línea
           10) configurar_banner_ssh ;;
            0) exit 0 ;;
            *) echo -e "${ROJO}❌ ¡Opción inválida!${NC}"; read -p "$(echo -e ${ROSA_CLARO}Presiona Enter para continuar...${NC})" ;;
        esac
    done
fi
