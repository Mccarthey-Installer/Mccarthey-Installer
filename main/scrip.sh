#!/bin/bash

# Definir rutas
export REGISTROS="/diana/reg.txt"
export HISTORIAL="/alexia/log.txt"
export PIDFILE="/Abigail/mon.pid"

# Crear directorios si no existen
mkdir -p $(dirname $REGISTROS)
mkdir -p $(dirname $HISTORIAL)
mkdir -p $(dirname $PIDFILE)

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
crear_usuario() {
    clear
    echo "===== 🤪 CREAR USUARIO SSH ====="
    read -p "👤 Nombre del usuario: " usuario
    read -p "🔑 Contraseña: " clave
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    # Validar entradas
    if [[ -z "$usuario" || -z "$clave" || -z "$dias" || -z "$moviles" ]]; then
        echo "❌ Todos los campos son obligatorios."
        read -p "Presiona Enter para continuar..."
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo "❌ Días y móviles deben ser números."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Verificar si el usuario ya existe en el sistema
    if id "$usuario" >/dev/null 2>&1; then
        echo "❌ El usuario $usuario ya existe en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuario en el sistema Linux
    if ! useradd -M -s /sbin/nologin "$usuario" 2>/dev/null; then
        echo "❌ Error al crear el usuario en el sistema."
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Establecer la contraseña
    if ! echo "$usuario:$clave" | chpasswd 2>/dev/null; then
        echo "❌ Error al establecer la contraseña."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Configurar fecha de expiración en el sistema (a las 00:00 del día siguiente al último día)
    fecha_expiracion_sistema=$(date -d "+$((dias + 1)) days" "+%Y-%m-%d")
    if ! chage -E "$fecha_expiracion_sistema" "$usuario" 2>/dev/null; then
        echo "❌ Error al establecer la fecha de expiración."
        userdel "$usuario" 2>/dev/null
        read -p "Presiona Enter para continuar..."
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
    echo "✅ Usuario creado correctamente:"
    echo "👤 Usuario: $usuario"
    echo "🔑 Clave: $clave"
    echo "📅 Expira: $fecha_expiracion"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo "===== 📝 RESUMEN DE REGISTRO ====="
    echo "👤 Usuario    📅 Expira          ⏳ Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-18s %-12s %-12s %s\n" "$usuario:$clave" "$fecha_expiracion" "$dias días" "$moviles" "$fecha_creacion"
    echo "=============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros
# Función para ver registros
ver_registros() {
    clear
    echo "===== 🌸 REGISTROS ====="
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira    ⏳  Días   📲 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=1
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            fecha_creacion="$fecha_creacion1 $fecha_creacion2"
            # Usar la fecha de expiración directamente, ya está en formato dd/mes/YYYY
            printf "%-2s %-11s %-10s %-16s %-8s %-8s\n" "$count" "$usuario" "$clave" "$fecha_expiracion" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
    fi
    read -p "Presiona Enter para continuar..."
}
# Función para mostrar un mini registro
mini_registro() {
    clear
    echo "==== 📋 MINI REGISTRO ====="
    echo "👤 Nombre  🔑 Contraseña   ⏳ Días   📱 Móviles"
    if [[ ! -f $REGISTROS || ! -s $REGISTROS ]]; then
        echo "No hay registros disponibles."
    else
        count=0
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion1 fecha_creacion2; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            dias_restantes=$(calcular_dias_restantes "$fecha_expiracion" "$dias")
            printf "%-12s %-16s %-10s %-10s\n" "$usuario" "$clave" "$dias_restantes" "$moviles"
            ((count++))
        done < $REGISTROS
        echo "==========================================="
        echo "TOTAL: $count usuarios"
    fi
    echo "Presiona Enter para continuar... ✨"
    read
}

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


        
                    
        
                    # Función para monitorear conexiones en segundo plano
monitorear_conexiones() {
    # Archivo de log para monitoreo
    LOG="/var/log/monitoreo_conexiones.log"
    # Intervalo de verificación en segundos
    INTERVALO=5

    # Bucle infinito para monitorear continuamente
    while true; do
        # Verificar si el archivo de registros existe
        [[ ! -f "$REGISTROS" ]] && { echo "$(date '+%Y-%m-%d %H:%M:%S'): No existe $REGISTROS." >> "$LOG"; sleep "$INTERVALO"; continue; }

        # Crear archivos temporales para procesar registros
        TEMP_FILE=$(mktemp "${REGISTROS}.tmp.XXXXXX") || { echo "$(date '+%Y-%m-%d %H:%M:%S'): Error archivo temporal." >> "$LOG"; sleep "$INTERVALO"; continue; }
        TEMP_FILE_NEW=$(mktemp "${REGISTROS}.tmp.new.XXXXXX") || { rm -f "$TEMP_FILE"; echo "$(date '+%Y-%m-%d %H:%M:%S'): Error archivo temporal nuevo." >> "$LOG"; sleep "$INTERVALO"; continue; }
        cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || { rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"; echo "$(date '+%Y-%m-%d %H:%M:%S'): Error copiando $REGISTROS." >> "$LOG"; sleep "$INTERVALO"; continue; }
        > "$TEMP_FILE_NEW"

        # Leer cada línea del archivo de registros
        while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do
            usuario=${user_data%%:*}
            clave=${user_data#*:}
            [[ -z "$usuario" ]] && continue

            # Verificar si el usuario existe en el sistema
            if id "$usuario" &>/dev/null; then
                # Contar conexiones activas (sshd y dropbear)
                CONEXIONES=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))
                MOVILES_NUM=$(echo "$moviles" | grep -oE '[0-9]+' || echo "1")
                # Verificar si el usuario está bloqueado
                [[ -n $(grep "^$usuario:!" /etc/shadow) ]] && CONEXIONES=0

                # Limitar conexiones si exceden el número de móviles permitidos
                if [[ $CONEXIONES -gt $MOVILES_NUM ]]; then
                    PIDS=($(ps -u "$usuario" -o pid=,comm= | awk '$2=="sshd" || $2=="dropbear"{print $1}' | tail -n +$((MOVILES_NUM+1))))
                    for PID in "${PIDS[@]}"; do
                        kill -9 "$PID" 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Sesión extra de '$usuario' (PID $PID) cerrada." >> "$LOG"
                    done
                fi

                # Archivo temporal para estado de conexión
                TMP_STATUS="/tmp/status_${usuario}.tmp"
                NEW_FECHA_CREACION="$fecha_creacion"

                # Verificar estado previo (si estaba conectado antes)
                PREV_CONEXIONES=0
                HORA_CONEXION=""
                if [[ -f "$TMP_STATUS" && -s "$TMP_STATUS" ]]; then
                    HORA_CONEXION=$(cut -d'|' -f1 "$TMP_STATUS")
                    if [[ "$HORA_CONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                        PREV_CONEXIONES=$(cat "$TMP_STATUS" | grep -q "CONNECTED" && echo 1 || echo 0)
                    else
                        # Eliminar archivo temporal inválido
                        rm -f "$TMP_STATUS" 2>/dev/null
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario - Archivo temporal inválido eliminado." >> "$LOG"
                        HORA_CONEXION=""
                    fi
                fi

                # Si hay conexiones activas
                if [[ $CONEXIONES -gt 0 ]]; then
                    # Si es una nueva conexión o el archivo temporal no existe/válido
                    if [[ $PREV_CONEXIONES -eq 0 || ! -f "$TMP_STATUS" || ! -s "$TMP_STATUS" || -z "$HORA_CONEXION" ]]; then
                        HORA_CONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                        echo "$HORA_CONEXION|CONNECTED" > "$TMP_STATUS"
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION." >> "$LOG"
                        NEW_FECHA_CREACION="$HORA_CONEXION"
                    fi
                # Si no hay conexiones activas pero estaba conectado antes
                elif [[ $PREV_CONEXIONES -gt 0 && -n "$HORA_CONEXION" ]]; then
                    HORA_DESCONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                    START_SECONDS=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                    END_SECONDS=$(date -d "$HORA_DESCONEXION" +%s 2>/dev/null)
                    if [[ -n "$START_SECONDS" && -n "$END_SECONDS" && $START_SECONDS -le $END_SECONDS ]]; then
                        DURATION_SECONDS=$((END_SECONDS - START_SECONDS))
                        DURATION=$(printf '%02d:%02d:%02d' $((DURATION_SECONDS/3600)) $(((DURATION_SECONDS%3600)/60)) $((DURATION_SECONDS%60)))
                        echo "$usuario|$HORA_CONEXION|$HORA_DESCONEXION|$DURATION" >> "$HISTORIAL"
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Duración: $DURATION." >> "$LOG"
                        rm -f "$TMP_STATUS" 2>/dev/null
                        NEW_FECHA_CREACION=""
                    else
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): Error al registrar desconexión de $usuario (fechas inválidas)." >> "$LOG"
                        rm -f "$TMP_STATUS" 2>/dev/null
                        NEW_FECHA_CREACION=""
                    fi
                fi

                # Escribir en el archivo temporal nuevo
                echo "$usuario:$clave $fecha_expiracion $dias $moviles $NEW_FECHA_CREACION" >> "$TEMP_FILE_NEW"
            else
                # Mantener registro si el usuario no existe en el sistema
                echo "$usuario:$clave $fecha_expiracion $dias $moviles $fecha_creacion" >> "$TEMP_FILE_NEW"
            fi
        done < "$TEMP_FILE"

        # Reemplazar archivo de registros y limpiar temporales
        mv "$TEMP_FILE_NEW" "$REGISTROS" 2>/dev/null && sync || { echo "$(date '+%Y-%m-%d %H:%M:%S'): Error reemplazando $REGISTROS." >> "$LOG"; rm -f "$TEMP_FILE" "$TEMP_FILE_NEW"; sleep "$INTERVALO"; continue; }
        rm -f "$TEMP_FILE" 2>/dev/null
        sleep "$INTERVALO"
    done
}

# Función para verificar usuarios online
verificar_online() {
    clear
    echo "===== ✅ USUARIOS ONLINE ====="
    # Mapa para traducir meses al español
    declare -A month_map=(
        ["Jan"]="enero" ["Feb"]="febrero" ["Mar"]="marzo" ["Apr"]="abril"
        ["May"]="mayo" ["Jun"]="junio" ["Jul"]="julio" ["Aug"]="agosto"
        ["Sep"]="septiembre" ["Oct"]="octubre" ["Nov"]="noviembre" ["Dec"]="diciembre"
    )

    # Crear archivo de historial si no existe
    [[ ! -f "$HISTORIAL" ]] && touch "$HISTORIAL"
    # Verificar si existe el archivo de registros
    if [[ ! -f "$REGISTROS" || ! -s "$REGISTROS" ]]; then
        echo "❌ No hay registros de usuarios. 📂"
        read -p "Presiona Enter para continuar... ✨"
        return 1
    fi

    # Imprimir encabezado
    printf "%-14s %-12s %-10s %-25s\n" "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo "-----------------------------------------------------------------"

    TOTAL_CONEXIONES=0
    TOTAL_USUARIOS=0
    INACTIVOS=0

    # Leer archivo de registros
    while IFS=' ' read -r user_data fecha_expiracion dias moviles fecha_creacion; do
        usuario=${user_data%%:*}
        clave=${user_data#*:}
        [[ -z "$usuario" ]] && continue

        # Verificar si el usuario existe en el sistema
        if id "$usuario" &>/dev/null; then
            ((TOTAL_USUARIOS++))
            ESTADO="☑️ 0"
            DETALLES="😴 Nunca conectado"
            MOVILES_NUM=$(echo "$moviles" | grep -oE '[0-9]+' || echo "1")

            # Verificar si el usuario está bloqueado
            if grep -q "^$usuario:!" /etc/shadow; then
                DETALLES="🔒 Usuario bloqueado"
                ((INACTIVOS++))
                ESTADO="🔴 BLOQ"
            else
                # Contar conexiones activas
                CONEXIONES=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))
                if [[ $CONEXIONES -gt 0 ]]; then
                    ESTADO="✅ $CONEXIONES"
                    TOTAL_CONEXIONES=$((TOTAL_CONEXIONES + CONEXIONES))

                    # Verificar conexiones activas y calcular tiempo conectado
                    TMP_STATUS="/tmp/status_${usuario}.tmp"
                    if [[ -f "$TMP_STATUS" && -s "$TMP_STATUS" ]]; then
                        HORA_CONEXION=$(cut -d'|' -f1 "$TMP_STATUS")
                        if [[ "$HORA_CONEXION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                            START_SECONDS=$(date -d "$HORA_CONEXION" +%s 2>/dev/null)
                            NOW_SECONDS=$(date +%s)
                            if [[ -n "$START_SECONDS" && -n "$NOW_SECONDS" ]]; then
                                ELAPSED_SEC=$((NOW_SECONDS - START_SECONDS))
                                if (( ELAPSED_SEC < 0 )); then
                                    # Tiempo negativo, reiniciar contador
                                    HORA_CONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                                    echo "$HORA_CONEXION|CONNECTED" > "$TMP_STATUS"
                                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION (tiempo negativo, archivo recreado)." >> "/var/log/monitoreo_conexiones.log"
                                    ELAPSED_SEC=0
                                fi
                                H=$((ELAPSED_SEC / 3600))
                                M=$(((ELAPSED_SEC % 3600) / 60))
                                S=$((ELAPSED_SEC % 60))
                                DETALLES=$(printf "⏰ %02d:%02d:%02d" $H $M $S)
                            else
                                # Error al obtener fechas, reiniciar contador
                                HORA_CONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                                echo "$HORA_CONEXION|CONNECTED" > "$TMP_STATUS"
                                echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION (error de fechas, archivo recreado)." >> "/var/log/monitoreo_conexiones.log"
                                DETALLES="⏰ 00:00:00"
                            fi
                        else
                            # Archivo temporal inválido, crear nuevo
                            HORA_CONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                            echo "$HORA_CONEXION|CONNECTED" > "$TMP_STATUS"
                            echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION (archivo inválido, recreado)." >> "/var/log/monitoreo_conexiones.log"
                            DETALLES="⏰ 00:00:00"
                        fi
                    else
                        # Archivo temporal no existe o está vacío, crear nuevo
                        HORA_CONEXION=$(date +"%Y-%m-%d %H:%M:%S")
                        echo "$HORA_CONEXION|CONNECTED" > "$TMP_STATUS"
                        echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado en $HORA_CONEXION (archivo creado)." >> "/var/log/monitoreo_conexiones.log"
                        DETALLES="⏰ 00:00:00"
                    fi
                else
                    # Usuario desconectado: eliminar archivo temporal para reiniciar contador
                    TMP_STATUS="/tmp/status_${usuario}.tmp"
                    rm -f "$TMP_STATUS" 2>/dev/null
                    # Buscar última desconexión en el historial (si existe)
                    ULTIMO_LOGOUT=""
                    if [[ -f "$HISTORIAL" ]]; then
                        ULTIMO_LOGOUT=$(grep -E "^${usuario}\|" "$HISTORIAL" | tail -n1 | awk -F'|' '{print $3}')
                    fi
                    if [[ -n "$ULTIMO_LOGOUT" ]]; then
                        # Intentar parsear y formatear la fecha de forma segura
                        if START_SECONDS=$(date -d "$ULTIMO_LOGOUT" +%s 2>/dev/null); then
                            # Día sin ceros a la izquierda
                            DIA=$(date -d "$ULTIMO_LOGOUT" +"%d" | sed 's/^0*//')
                            # Abreviatura del mes (Jan, Feb, ...)
                            MES_ABBR=$(date -d "$ULTIMO_LOGOUT" +"%b")
                            # Hora en formato 12h con am/pm en minúsculas
                            HORA=$(date -d "$ULTIMO_LOGOUT" +"%I:%M %p" 2>/dev/null | tr '[:upper:]' '[:lower:]')
                            # Traducir abreviatura usando month_map
                            MES=${month_map[$MES_ABBR]:-$MES_ABBR}
                            DETALLES="📅 Última: ${DIA} de ${MES}:${HORA}"
                        else
                            # Si date -d falla, mostrar el valor crudo
                            DETALLES="📅 Última: $ULTIMO_LOGOUT"
                        fi
                    else
                        DETALLES="😴 Nunca conectado"
                    fi
                    ((INACTIVOS++))
                fi
            fi
            # Imprimir información del usuario
            printf "%-14s %-12s %-10s %-25s\n" "$usuario" "$ESTADO" "📲 $MOVILES_NUM" "$DETALLES"
        fi
    done < "$REGISTROS"

    # Imprimir resumen
    echo
    echo "Total de Online: $TOTAL_CONEXIONES Total usuarios: $TOTAL_USUARIOS Inactivos: $INACTIVOS"
    echo "================================================="
    read -p "Presiona Enter para continuar... ✨"
}

# Iniciar monitoreo de conexiones con nohup si no está corriendo
if [[ ! -f "$PIDFILE" ]] || ! ps -p "$(cat "$PIDFILE" 2>/dev/null)" >/dev/null 2>&1; then
    # Rotar el log si es demasiado grande (> 100 MB)
    if [[ -f "/var/log/monitoreo_conexiones.log" && $(stat -f %z "/var/log/monitoreo_conexiones.log" 2>/dev/null || stat -c %s "/var/log/monitoreo_conexiones.log") -gt 104857600 ]]; then
        mv "/var/log/monitoreo_conexiones.log" "/var/log/monitoreo_conexiones.log.bak"
        touch "/var/log/monitoreo_conexiones.log"
    fi
    rm -f "$PIDFILE"
    nohup bash -c "source $0; monitorear_conexiones" >> /var/log/monitoreo_conexiones.log 2>&1 &
    sleep 1
    if ps -p $! >/dev/null 2>&1; then
        echo $! > "$PIDFILE"
        echo "🚀 Monitoreo iniciado en segundo plano (PID: $!)."
    else
        echo "❌ Error al iniciar el monitoreo. Revisa /var/log/monitoreo_conexiones.log."
    fi
else
    echo "⚠️ Monitoreo ya está corriendo (PID: $(cat "$PIDFILE"))."
fi






# Menú principal
while true; do
    clear
    echo "===== MENÚ SSH WEBSOCKET ====="
    echo "1.🦁 Crear usuario"
    echo "2. Ver registros"
    echo "3. Mini registro"
    echo "4. Crear múltiples usuarios"
    echo "5. Eliminar múltiples usuarios"
    echo "6. Verificar usuarios online"
    echo "0. Salir"
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1)
            crear_usuario
            ;;
        2)
            ver_registros
            ;;
        3)
            mini_registro
            ;;
        4)
            crear_multiples_usuarios
            ;;
        5)
            eliminar_multiples_usuarios
            ;;
        6)
            verificar_online
            ;;
        0)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción inválida."
            read -p "Presiona Enter para continuar..."
            ;;
    esac
done
