import socket, threading, sys

# Validación de argumentos
if len(sys.argv) < 4:
    print("Uso: python3 proxy.py <puerto_proxy> <puerto_destino> <response>")
    sys.exit(1)

listen_port = int(sys.argv[1])
target_port = int(sys.argv[2])
response_code = sys.argv[3]

def handle(conn, addr):
    try:
        data = conn.recv(4096)
        if not data:
            conn.close()
            return

        host = ''
        for line in data.decode().split('\r\n'):
            if line.lower().startswith('host:'):
                host = line.split(':')[1].strip()
                break

        if not host:
            conn.close()
            return

        # Conexión con el destino
        target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target.connect(('127.0.0.1', target_port))

        # Enviar respuesta WebSocket si es 101
        if response_code == '101':
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "\r\n"
            )
            conn.send(response.encode())

        target.send(data)

        # Encaminamiento de datos
        threading.Thread(target=pipe, args=(conn, target)).start()
        threading.Thread(target=pipe, args=(target, conn)).start()

    except Exception as e:
        conn.close()

def pipe(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.send(data)
    finally:
        src.close()
        dst.close()

def start():
    print(f"[+] Proxy activo en puerto {listen_port} redirigiendo al {target_port} con respuesta {response_code}")
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind(('0.0.0.0', listen_port))
    server.listen(100)
    while True:
        conn, addr = server.accept()
        threading.Thread(target=handle, args=(conn, addr)).start()

if __name__ == "__main__":
    start()
