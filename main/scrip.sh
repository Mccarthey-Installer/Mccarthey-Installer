#!/bin/bash

# Archivo para almacenar registros de usuarios
REGISTRO_FILE="/root/ssh_users.txt"
# Directorio temporal para cálculos
TEMP_DIR="/tmp"
# Colores para la interfaz
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m" # Sin color

# Función para calcular la fecha de expiración
calcular_expiracion() {
    local dias=$1
    date -d "+$dias days" +"%Y-%m-%d %H:%M:%S"
}

# Función para formatear fecha a español (dd/mes/yyyy)
formato_fecha() {
    local fecha=$1
    meses=("enero" "febrero" "marzo" "abril" "mayo" "junio" "julio" "agosto" "septiembre" "octubre" "noviembre" "diciembre")
    dia=$(date -d "$fecha" +"%d")
    mes=$(date -d "$fecha" +"%m")
    anio=$(date -d "$fecha" +"%Y")
    mes_index=$((10#$mes - 1))
    echo "$dia/${meses[$mes_index]}/$anio"
}

# Función para crear un usuario
crear_usuario() {
    clear
    echo -e "${GREEN}===== 🤪 CREAR USUARIO SSH =====${NC}"
    read -p "👤 Nombre del usuario: " username
    read -p "🔑 Contraseña: " password
    read -p "📅 Días de validez: " dias
    read -p "📱 ¿Cuántos móviles? " moviles

    if id "$username" >/dev/null 2>&1; then
        echo -e "${RED}Error: El usuario $username ya existe.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Los días y móviles deben ser números enteros.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    useradd -M -s /bin/false "$username"
    echo "$username:$password" | chpasswd

    fecha_creacion=$(date +"%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    echo "$username:$password:$fecha_expiracion:$dias:$moviles:$fecha_creacion" >> "$REGISTRO_FILE"

    echo -e "${GREEN}✅ Usuario creado correctamente:${NC}"
    echo "👤 Usuario: $username"
    echo "🔑 Clave: $password"
    echo "📅 Expira: $(formato_fecha "$fecha_expiracion")"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo -e "${YELLOW}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo "👤 Usuario    📅 Expira          ⏳  Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-20s %-12s %-12s %s\n" "$username:$password" "$(formato_fecha "$fecha_expiracion")" "$dias días" "$moviles" "$fecha_creacion"
    echo "==============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros (corrigiendo días y móviles)
ver_registros() {
    clear
    echo -e "${GREEN}===== 🌸 REGISTROS =====${NC}"
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira          ⏳  Días   📲 Móviles"
    echo "---------------------------------------------------------------"

    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        if [[ -z "$user" || -z "$pass" || -z "$expira" || -z "$dias" || -z "$moviles" || -z "$creado" ]]; then
            continue
        fi
        # Eliminar ceros a la izquierda de días y móviles
        dias_sin_ceros=$((10#$dias))
        moviles_sin_ceros=$((10#$moviles))
        printf "%-2s %-12s %-12s %-18s %-10s %s\n" "$count" "$user" "$pass" "$(formato_fecha "$expira")" "$dias_sin_ceros" "$moviles_sin_ceros"
        ((count++))
    done < "$REGISTRO_FILE"

    echo "---------------------------------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Función que cierra las sesiones activas de un usuario con loginctl
cerrar_sesiones_activa() {
    local user=$1
    # Listar sesiones activas del usuario
    sessions=$(loginctl list-sessions --no-legend | awk '{print $1,$3}' | grep -w "$user" | awk '{print $1}')
    for session in $sessions; do
        loginctl terminate-session "$session"
    done
}

# Función mejorada para eliminar usuarios, acepta múltiples nombres o números separados por espacios.
eliminar_usuario() {
    clear
    echo -e "${GREEN}===== 🗑️ ELIMINAR USUARIO SSH =====${NC}"

    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados para eliminar.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    echo -e "${YELLOW}Lista de usuarios registrados:${NC}"
    echo "Nº 👩 Usuario"
    echo "-----------------"
    mapfile -t usuarios < <(cut -d':' -f1 "$REGISTRO_FILE")
    count=1
    for u in "${usuarios[@]}"; do
        printf "%-2s %s\n" "$count" "$u"
        ((count++))
    done
    echo "-----------------"

    read -p "👤 Nombre(s) o número(s) de usuario(s) a eliminar (separados por espacio): " -a lista_entrada

    # Crear lista de usuarios a eliminar a partir de entrada numérica o nombres
    usuarios_a_eliminar=()
    for item in "${lista_entrada[@]}"; do
        if [[ "$item" =~ ^[0-9]+$ ]]; then
            # Si el número es válido, buscar usuario por índice
            idx=$((item - 1))
            if (( idx >= 0 && idx < ${#usuarios[@]} )); then
                usuarios_a_eliminar+=("${usuarios[$idx]}")
            else
                echo -e "${RED}Error: No existe el número de usuario $item.${NC}"
            fi
        else
            # Validar que el nombre exista en usuarios
            if [[ " ${usuarios[*]} " == *" $item "* ]]; then
                usuarios_a_eliminar+=("$item")
            else
                echo -e "${RED}Error: El usuario $item no existe en el registro.${NC}"
            fi
        fi
    done

    if [[ ${#usuarios_a_eliminar[@]} -eq 0 ]]; then
        echo -e "${RED}No se seleccionaron usuarios válidos para eliminar.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    for user in "${usuarios_a_eliminar[@]}"; do
        if ! id "$user" >/dev/null 2>&1; then
            echo -e "${YELLOW}El usuario $user no existe en el sistema, se omitirá.${NC}"
            # Igual borrar de registro
            grep -v "^$user:" "$REGISTRO_FILE" > "$TEMP_DIR/ssh_users_temp.txt"
            mv "$TEMP_DIR/ssh_users_temp.txt" "$REGISTRO_FILE"
            continue
        fi
        # Cerrar sesiones activas antes de eliminar el usuario
        cerrar_sesiones_activa "$user"
        # Eliminar usuario del sistema completo con su directorio (si quieres)
        userdel -r "$user" 2>/dev/null || userdel "$user"
        # Eliminar del registro
        grep -v "^$user:" "$REGISTRO_FILE" > "$TEMP_DIR/ssh_users_temp.txt"
        mv "$TEMP_DIR/ssh_users_temp.txt" "$REGISTRO_FILE"
        echo -e "${GREEN}✅ Usuario $user eliminado correctamente.${NC}"
    done

    read -p "Presiona Enter para continuar..."
}

# Menú principal
while true; do
    clear
    echo -e "${YELLOW}===== MENÚ SSH WEBSOCKET =====${NC}"
    echo "1. Crear usuario"
    echo "2. Ver registros"
    echo "3. Eliminar usuario"
    echo "0. Salir"
    read -p "Selecciona una opción [0-3]: " opcion

    case $opcion in
        1) crear_usuario ;;
        2) ver_registros ;;
        3) eliminar_usuario ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; read -p "Presiona Enter para continuar..." ;;
    esac
done
