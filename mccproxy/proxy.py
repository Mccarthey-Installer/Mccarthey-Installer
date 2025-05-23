import socket
import threading
import select
import logging
import os

# Configuración de logging
logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(message)s', datefmt='%H:%M:%S')

# Cargar puertos desde archivos externos
def cargar_puertos():
    try:
        with open('/etc/mccproxy_ports') as f:
            return [int(p.strip()) for p in f.read().replace(',', ' ').split()]
    except:
        return [8080]  # Puerto por defecto

LISTEN_PORTS = cargar_puertos()
DESTINATION_HOST = '127.0.0.1'
DESTINATION_PORT = 444  # Dropbear u otro

# Encabezado WebSocket para handshake
WS_HANDSHAKE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    "Sec-WebSocket-Accept: dummykey==\r\n\r\n"
)

def handle_client(client_socket):
    try:
        request = client_socket.recv(1024)
        if not request:
            client_socket.close()
            return

        # Detectar y responder handshake WebSocket sin cerrar conexión
        if b'Upgrade: websocket' in request:
            logging.info(f"[HANDSHAKE] WebSocket detectado")
            client_socket.sendall(WS_HANDSHAKE.encode())
            # No se cierra el socket

        # Redirigir tráfico al destino (Dropbear)
        remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote_socket.connect((DESTINATION_HOST, DESTINATION_PORT))

        sockets = [client_socket, remote_socket]
        while True:
            read_sockets, _, _ = select.select(sockets, [], [])
            for sock in read_sockets:
                data = sock.recv(4096)
                if not data:
                    client_socket.close()
                    remote_socket.close()
                    return
                if sock is client_socket:
                    remote_socket.sendall(data)
                else:
                    client_socket.sendall(data)
    except Exception as e:
        logging.error(f"Error manejando cliente: {e}")
        try:
            client_socket.close()
        except:
            pass

def start_proxy(port):
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('0.0.0.0', port))
        server.listen(100)
        logging.info(f"[PROXY] Escuchando en puerto {port}")
        while True:
            client_socket, addr = server.accept()
            threading.Thread(target=handle_client, args=(client_socket,)).start()
    except Exception as e:
        logging.error(f"Error al iniciar proxy en puerto {port}: {e}")

if __name__ == '__main__':
    for port in LISTEN_PORTS:
        threading.Thread(target=start_proxy, args=(port,)).start()
