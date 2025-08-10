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
    # Lista de meses en español
    meses=("enero" "febrero" "marzo" "abril" "mayo" "junio" "julio" "agosto" "septiembre" "octubre" "noviembre" "diciembre")
    dia=$(date -d "$fecha" +"%d")
    mes=$(date -d "$fecha" +"%m")
    anio=$(date -d "$fecha" +"%Y")
    # Convertir mes numérico a texto (restamos 1 porque los índices en bash comienzan en 0)
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

    # Validar que el usuario no exista
    if id "$username" >/dev/null 2>&1; then
        echo -e "${RED}Error: El usuario $username ya existe.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Validar que los días y móviles sean números
    if ! [[ "$dias" =~ ^[0-9]+$ ]] || ! [[ "$moviles" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Los días y móviles deben ser números enteros.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Crear usuario en el sistema
    useradd -M -s /bin/false "$username"
    echo "$username:$password" | chpasswd

    # Calcular fecha de creación y expiración
    fecha_creacion=$(date +"%Y-%m-%d %H:%M:%S")
    fecha_expiracion=$(calcular_expiracion $dias)

    # Guardar en el archivo de registro
    echo "$username:$password:$fecha_expiracion:$dias:$moviles:$fecha_creacion" >> "$REGISTRO_FILE"

    # Mostrar información del usuario creado
    echo -e "${GREEN}✅ Usuario creado correctamente:${NC}"
    echo "👤 Usuario: $username"
    echo "🔑 Clave: $password"
    echo "📅 Expira: $(formato_fecha "$fecha_expiracion")"
    echo "📱 Límite móviles: $moviles"
    echo "📅 Creado: $fecha_creacion"
    echo -e "${YELLOW}===== 📝 RESUMEN DE REGISTRO =====${NC}"
    echo "👤 Usuario    📅 Expira          ⏳ Días       📱 Móviles   📅 Creado"
    echo "---------------------------------------------------------------"
    printf "%-12s %-20s %-12s %-12s %s\n" "$username:$password" "$(formato_fecha "$fecha_expiracion")" "$dias días" "$moviles" "$fecha_creacion"
    echo "==============================================================="
    read -p "Presiona Enter para continuar..."
}

# Función para ver registros
ver_registros() {
    clear
    echo -e "${GREEN}===== 🌸 REGISTROS =====${NC}"
    echo "Nº 👩 Usuario 🔒 Clave   📅 Expira          ⏳ Días   📲 Móviles"
    echo "---------------------------------------------------------------"
    
    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Leer el archivo de registros
    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        # Validar que los campos no estén vacíos o corruptos
        if [[ -z "$user" ]] || [[ -z "$pass" ]] || [[ -z "$expira" ]] || [[ -z "$dias" ]] || [[ -z "$moviles" ]] || [[ -z "$creado" ]]; then
            continue
        fi
        printf "%-2s %-12s %-12s %-18s %-10s %s\n" "$count" "$user" "$pass" "$(formato_fecha "$expira")" "$dias" "$moviles"
        ((count++))
    done < "$REGISTRO_FILE"
    
    echo "---------------------------------------------------------------"
    read -p "Presiona Enter para continuar..."
}

# Función para eliminar usuario
eliminar_usuario() {
    clear
    echo -e "${GREEN}===== 🗑️ ELIMINAR USUARIO SSH =====${NC}"
    
    # Verificar si hay usuarios registrados
    if [[ ! -f "$REGISTRO_FILE" ]] || [[ ! -s "$REGISTRO_FILE" ]]; then
        echo -e "${RED}No hay usuarios registrados para eliminar.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Mostrar lista de usuarios
    echo -e "${YELLOW}Lista de usuarios registrados:${NC}"
    echo "Nº 👩 Usuario"
    echo "-----------------"
    count=1
    while IFS=':' read -r user pass expira dias moviles creado; do
        if [[ -z "$user" ]]; then
            continue
        fi
        printf "%-2s %s\n" "$count" "$user"
        ((count++))
    done < "$REGISTRO_FILE"
    echo "-----------------"

    # Solicitar el nombre del usuario a eliminar
    read -p "👤 Nombre del usuario a eliminar: " username

    # Verificar si el usuario existe en el sistema
    if ! id "$username" >/dev/null 2>&1; then
        echo -e "${RED}Error: El usuario $username no existe en el sistema.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Verificar si el usuario está en el registro
    if ! grep -q "^$username:" "$REGISTRO_FILE"; then
        echo -e "${RED}Error: El usuario $username no está en el registro.${NC}"
        read -p "Presiona Enter para continuar..."
        return
    fi

    # Eliminar usuario del sistema
    userdel "$username"

    # Eliminar usuario del archivo de registro
    grep -v "^$username:" "$REGISTRO_FILE" > "$TEMP_DIR/ssh_users_temp.txt"
    mv "$TEMP_DIR/ssh_users_temp.txt" "$REGISTRO_FILE"

    echo -e "${GREEN}✅ Usuario $username eliminado correctamente.${NC}"
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
