1 #!/bin/bash
  2
  3 # Colores ANSI
  4 RED='\033[0;31m'
  5 GREEN='\033[0;32m'
  6 YELLOW='\033[1;33m'
  7 BLUE='\033[0;34m'
  8 CYAN='\033[0;36m'
  9 NC='\033[0m' # No Color
 10
 11 # Función para mostrar el menú
 12 mostrar_menu() {
 13     clear
 14     echo -e "${CYAN}=======================================${NC}"
 15     echo -e "${YELLOW}    SISTEMA DE GESTIÓN DE USUARIOS    ${NC}"
 16     echo -e "${CYAN}=======================================${NC}"
 17     echo -e "${GREEN}1. Crear usuario temporal${NC}"
 18     echo -e "${GREEN}2. Ver registro de usuarios${NC}"
 19     echo -e "${GREEN}3. Eliminar usuario${NC}"
 20     echo -e "${GREEN}4. Salir${NC}"
 21     echo -e "${CYAN}=======================================${NC}"
 22     echo -e -n "${BLUE}Seleccione una opción [1-4]: ${NC}"
 23 }
 24
 25 # Función para crear usuario
 26 crear_usuario() {
 27     read -p "Ingrese nombre de usuario: " USUARIO
 28     read -s -p "Ingrese contraseña: " CLAVE
 29     echo ""
 30     read -p "Ingrese días de validez: " DIAS
 31
 32     # Verifica si se proporcionaron los datos
 33     if [ -z "$USUARIO" ] || [ -z "$CLAVE" ] || [ -z "$DIAS" ]; then
 34         echo -e "${RED}Error: Todos los campos son requeridos${NC}"
 35         return 1
 36     fi
 37
 38     # Verifica si el usuario ya existe
 39     if id "$USUARIO" &>/dev/null; then
 40         echo -e "${RED}El usuario '$USUARIO' ya existe. No se puede crear.${NC}"
 41         return 1
 42     fi
 43
 44     # Crear el usuario con shellIMI bash y directorio home
 45     useradd -m -s /bin/bash "$USUARIO"
 46
 47     # Asignar contraseña
 48     echo "$USUARIO:$CLAVE" | chpasswd
 49
 50     # Calcular la fecha exacta de expiración
 51     EXPIRA=$(date -d "+$DIAS days" +%Y-%m-%d)
 52
 53     # Establecer la expiración
 54     chage -E "$EXPIRA" "$USUARIO"
 55
 56     # Formatear fecha bonita
 57     FECHA_FORMATO=$(date -d "$EXPIRA" +"%d de %B de %Y")
 58
 59     # Confirmación clara
 60     echo -e "\n${GREEN}===== USUARIO CREADO EXITOSAMENTE =====${NC}"
 61     echo -e "${CYAN}Usuario: ${YELLOW}$USUARIO${NC}"
 62     echo -e "${CYAN}Contraseña: ${YELLOW}$CLAVE${NC}"
 63     echo -e "${CYAN}Duración: ${YELLOW}$DIAS días${NC}"
 64     echo -e "${CYAN}Último día válido: ${YELLOW}$FECHA_FORMATO (vence a las 23:59)${NC}"
 65     echo -e "${GREEN}=======================================${NC}"
 66 }
 67
 68 # Función para ver registro de usuarios
 69 ver_registro() {
 70     echo -e "\n${CYAN}===== REGISTRO DE USUARIOS =====${NC}"
 71     i=1
 72     while IFS=: read -r username _ _ _ _ _ home _; do
 73         if [[ "$home" == /home/* ]]; then
 74             expiry=$(chage -l "$username" | grep "Account expires" | awk -F": " '{print $2}' || echo "No especificada")
 75             echo -e "${YELLOW}$i. ${CYAN}Usuario: ${GREEN}$username ${CYAN}Expiración: ${GREEN}$expiry${NC}"
 76             ((i++))
 77         fi
 78     done < /etc/passwd
 79     echo -e "${CYAN}===============================${NC}"
 80 }
 81
 82 # Función para eliminar usuario
 83 eliminar_usuario() {
 84     echo -e "\n${CYAN}===== ELIMINAR USUARIO =====${NC}"
 85     ver_registro
 86     echo -e -n "${BLUE}Ingrese el número del usuario a eliminar: ${NC}"
 87     read numero
 88
 89     # Obtener el nombre del usuario según el número
 90     i=1
 91     usuario_seleccionado=""
 92     while IFS=: read -r username _ _ _ _ _ home _; do
 93         if [[ "$home" == /home/* ]]; then
 94             if [ "$i" -eq "$numero" ]; then
 95                 usuario_seleccionado="$username"
 96                 break
 97             fi
 98             ((i++))
 99         fi
100     done < /etc/passwd
101
102     if [ -z "$usuario_seleccionado" ]; then
103         echo -e "${RED}Número de usuario inválido${NC}"
104         return 1
105     fi
106
107     echo -e "${YELLOW}Usuario seleccionado: ${GREEN}$usuario_seleccionado${NC}"
108     echo -e -n "${BLUE}¿Confirma la eliminación? (Presione Enter para confirmar, cualquier otra tecla para cancelar): ${NC}"
109     read -s -n 1 confirmacion
110     echo ""
111
112     if [ -z "$confirmacion" ]; then
113         userdel -r "$usuario_seleccionado" 2>/dev/null
114         if [ $? -eq 0 ]; then
115             echo -e "${GREEN}Usuario $usuario_seleccionado eliminado exitosamente${NC}"
116         else
117             echo -e "${RED}Error al eliminar el usuario${NC}"
118         fi
119     else
120         echo -e "${YELLOW}Operación cancelada${NC}"
121     fi
122 }
123
124 # Bucle principal del menú
125 while true; do
126     mostrar_menu
127     read opcion
128     case $opcion in
129         1)
130             crear_usuario
131             echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
132             read
133             ;;
134         2)
135             ver_registro
136             echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
137             read
138             ;;
139         3)
140             eliminar_usuario
141             echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
142             read
143             ;;
144         4)
145             echo -e "${GREEN}¡Hasta luego!${NC}"
146             exit 0
147             ;;
148         *)
149             echo -e "${RED}Opción inválida${NC}"
150             echo -e -n "${BLUE}Presione Enter para continuar...${NC}"
151             read
152             ;;
153     esac
154 done
