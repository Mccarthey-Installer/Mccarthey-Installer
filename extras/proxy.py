#!/usr/bin/env python3
# proxy.py - Proxy TCP con soporte para WebSocket y handshake SSH seguro

import socket
import threading
import sys
import logging
import signal
import time
from typing import Tuple, Optional

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("proxy.log")
    ]
)
logger = logging.getLogger(__name__)

class ProxyConfig:
    def __init__(self, listen_port: int, target_port: int, response_code: str):
        self.listen_host = "0.0.0.0"
        self.target_host = "127.0.0.1"
        self.listen_port = listen_port
        self.target_port = target_port
        self.response_code = response_code
        self.backlog = 100
        self.buffer_size = 4096
        self.timeout = 10

class ProxyServer:
    def __init__(self, config: ProxyConfig):
        self.config = config
        self.server_socket: Optional[socket.socket] = None
        self.running = False

    def validate_config(self) -> None:
        if not (1 <= self.config.listen_port <= 65535):
            raise ValueError("Puerto de escucha inválido.")
        if not (1 <= self.config.target_port <= 65535):
            raise ValueError("Puerto destino inválido.")
        if self.config.response_code not in ["101", "none"]:
            raise ValueError("Código de respuesta inválido. Usa '101' o 'none'.")

    def setup_socket(self) -> None:
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.settimeout(self.config.timeout)
        self.server_socket.bind((self.config.listen_host, self.config.listen_port))
        self.server_socket.listen(self.config.backlog)
        logger.info(f"Proxy en {self.config.listen_host}:{self.config.listen_port} -> {self.config.target_host}:{self.config.target_port} (res: {self.config.response_code})")

    def handle_client(self, client_sock: socket.socket, addr: Tuple[str, int]) -> None:
        logger.info(f"Conexión entrante: {addr[0]}:{addr[1]}")
        client_sock.settimeout(self.config.timeout)

        try:
            data = client_sock.recv(self.config.buffer_size)
            if not data:
                client_sock.close()
                return

            target_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            target_sock.settimeout(self.config.timeout)
            target_sock.connect((self.config.target_host, self.config.target_port))

            # Enviar respuesta WebSocket si se requiere
            if self.config.response_code == "101":
                response = (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    "\r\n"
                )
                client_sock.send(response.encode())
                logger.debug("Enviada respuesta WebSocket")

            # Esperar el banner del servidor SSH
            ssh_banner = target_sock.recv(self.config.buffer_size)
            client_sock.send(ssh_banner)

            # Ahora enviar datos del cliente
            target_sock.send(data)

            threading.Thread(target=self.pipe, args=(client_sock, target_sock)).start()
            threading.Thread(target=self.pipe, args=(target_sock, client_sock)).start()

        except Exception as e:
            logger.error(f"Error con {addr[0]}:{addr[1]}: {e}", exc_info=True)
            client_sock.close()

    def pipe(self, src: socket.socket, dst: socket.socket) -> None:
        try:
            while self.running:
                data = src.recv(self.config.buffer_size)
                if not data:
                    break
                dst.send(data)
        except:
            pass
        finally:
            src.close()
            dst.close()

    def start(self) -> None:
        self.running = True
        self.setup_socket()
        try:
            while self.running:
                try:
                    client_sock, addr = self.server_socket.accept()
                    threading.Thread(target=self.handle_client, args=(client_sock, addr)).start()
                except socket.timeout:
                    continue
        finally:
            self.shutdown()

    def shutdown(self) -> None:
        self.running = False
        if self.server_socket:
            self.server_socket.close()
            logger.info("Proxy detenido.")

def parse_arguments() -> ProxyConfig:
    if len(sys.argv) < 4:
        print("Uso: python3 proxy.py <puerto_proxy> <puerto_destino> <response_code>")
        sys.exit(1)
    return ProxyConfig(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3])

def main():
    proxy = None
    def signal_handler(sig, frame):
        if proxy:
            proxy.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        config = parse_arguments()
        proxy = ProxyServer(config)
        proxy.validate_config()
        proxy.start()
    except Exception as e:
        logger.error(f"Fallo al iniciar el proxy: {e}", exc_info=True)
        sys.exit(1)

if __name__ == "__main__":
    main()
