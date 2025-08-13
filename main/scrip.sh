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

# ================================
# FUNCIONES YA DEFINIDAS (ejemplo de 2 para mostrar)
# Aquí pondrías todas tus funciones de crear_usuario, ver_registros, etc.
# ================================
monitorear_conexiones() {
    LOG="/var/log/monitoreo_conexiones.log"
    INTERVALO=5

    while true; do
        [[ ! -f "$REGISTROS" ]] && { sleep "$INTERVALO"; continue; }

        TEMP_FILE=$(mktemp) || { sleep "$INTERVALO"; continue; }
        cp "$REGISTROS" "$TEMP_FILE" 2>/dev/null || { rm -f "$TEMP_FILE"; sleep "$INTERVALO"; continue; }
        TEMP_FILE_NEW=$(mktemp) || { rm -f "$TEMP_FILE"; sleep "$INTERVALO"; continue; }
        > "$TEMP_FILE_NEW"

        while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
            usuario=${userpass%%:*}
            [[ -z "$usuario" ]] && continue

            tmp_status="/tmp/status_${usuario}.tmp"
            conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

            if [[ $conexiones -gt 0 ]]; then
                if [[ ! -f "$tmp_status" ]]; then
                    hora_ini_sys=$(last -F "$usuario" | head -1 | awk '{print $4" "$5" "$6" "$7}')
                    if [[ -n "$hora_ini_sys" ]]; then
                        timestamp_ini=$(date -d "$hora_ini_sys" +%s 2>/dev/null)
                        if [[ -z "$timestamp_ini" ]]; then
                            timestamp_ini=$(date +%s)
                        fi
                        echo "$timestamp_ini" > "$tmp_status"
                    else
                        date +%s > "$tmp_status"
                    fi
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario conectado." >> "$LOG"
                fi
            else
                if [[ -f "$tmp_status" ]]; then
                    hora_ini_epoch=$(cat "$tmp_status")
                    hora_fin=$(date "+%Y-%m-%d %H:%M:%S")
                    rm -f "$tmp_status"
                    echo "$usuario|$(date -d @"$hora_ini_epoch" "+%Y-%m-%d %H:%M:%S")|$hora_fin" >> "$HISTORIAL"
                    echo "$(date '+%Y-%m-%d %H:%M:%S'): $usuario desconectado. Inicio: $(date -d @"$hora_ini_epoch" "+%Y-%m-%d %H:%M:%S") Fin: $hora_fin" >> "$LOG"
                fi
            fi

            echo "$userpass $fecha_exp $dias $moviles $fecha_crea $hora_crea" >> "$TEMP_FILE_NEW"
        done < "$TEMP_FILE"

        mv "$TEMP_FILE_NEW" "$REGISTROS" 2>/dev/null
        rm -f "$TEMP_FILE"
        sleep "$INTERVALO"
    done
}

# ================================
#  MODO MONITOREO DIRECTO (este bloque va DESPUÉS de la función)
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

verificar_online() {
    clear
    echo "===== ✅ USUARIOS ONLINE ====="
    printf "%-14s %-14s %-10s %-25s\n" "👤 USUARIO" "✅ CONEXIONES" "📱 MÓVILES" "⏰ TIEMPO CONECTADO"
    echo "-----------------------------------------------------------------"

    total_online=0
    total_usuarios=0
    inactivos=0

    if [[ ! -f "$REGISTROS" ]]; then
        echo "❌ No hay registros."
        read -p "Presiona Enter para continuar..."
        return
    fi

    while read -r userpass fecha_exp dias moviles fecha_crea hora_crea; do
        usuario=${userpass%%:*}
        (( total_usuarios++ ))

        # Ver cuántas conexiones SSH/Dropbear tiene
        conexiones=$(( $(ps -u "$usuario" -o comm= | grep -c "^sshd$") + $(ps -u "$usuario" -o comm= | grep -c "^dropbear$") ))

        estado="☑️ 0"
        detalle="😴 Nunca conectado"
        mov_txt="📲 $moviles"
        tmp_status="/tmp/status_${usuario}.tmp"

        if [[ $conexiones -gt 0 ]]; then
            estado="✅ $conexiones"
            (( total_online += conexiones ))

            if [[ -f "$tmp_status" ]]; then
                start_time=$(cat "$tmp_status")
                # Validar formato del tiempo
                if [[ "$start_time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                    start_s=$(date -d "$start_time" "+%s" 2>/dev/null)
                    now_s=$(date "+%s")
                    if [[ -n "$start_s" && "$start_s" =~ ^[0-9]+$ ]]; then
                        elapsed=$(( now_s - start_s ))
                        h=$(( elapsed / 3600 ))
                        m=$(( (elapsed % 3600) / 60 ))
                        s=$(( elapsed % 60 ))
                        detalle=$(printf "⏰ %02d:%02d:%02d" "$h" "$m" "$s")
                    else
                        detalle="⏰ Error en tiempo"
                    fi
                else
                    detalle="⏰ Formato inválido"
                fi
            else
                detalle="⏰ 00:00:00"
            fi
        else
            rm -f "$tmp_status"
            ult=$(grep "^$usuario|" "$HISTORIAL" | tail -1 | awk -F'|' '{print $3}')
            if [[ -n "$ult" ]]; then
                ult_fmt=$(date -d "$ult" +"%d de %B %I:%M %p" 2>/dev/null || echo "Fecha inválida")
                detalle="📅 Última: $ult_fmt"
            else
                (( inactivos++ ))
            fi
        fi

        printf "%-14s %-14s %-10s %-25s\n" "$usuario" "$estado" "$mov_txt" "$detalle"
    done < "$REGISTROS"

    echo "-----------------------------------------------------------------"
    echo "Total de Online: $total_online  Total usuarios: $total_usuarios  Inactivos: $inactivos"
    echo "================================================"
    read -p "Presiona Enter para continuar..."
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


        




# Menú principal
while true; do
    clear
    echo "===== MENÚ SSH WEBSOCKET ====="
    echo "1. ⏰ crear usuario"
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
