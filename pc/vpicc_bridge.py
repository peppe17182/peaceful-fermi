import socket
import sys
import threading
import time
import struct
import argparse

# Default port configurations
DEFAULT_VPCD_PORT = 35963
DEFAULT_PHONE_PORT = 35963

def log(msg):
    print(f"[*] {msg}")

def safe_recv(sock, num_bytes):
    data = b""
    while len(data) < num_bytes:
        packet = sock.recv(num_bytes - len(data))
        if not packet:
            return None
        data += packet
    return data

def relay_loop(src_sock, dst_sock, src_name, dst_name, exit_event):
    """
    Relays vpicc protocol messages from src_sock to dst_sock.
    Message format: [2 bytes big-endian length] [payload]
    """
    try:
        while not exit_event.is_set():
            # 1. Read 2-byte length prefix
            len_data = safe_recv(src_sock, 2)
            if len_data is None:
                log(f"{src_name} closed the connection.")
                break
            
            length = struct.unpack("!H", len_data)[0]
            
            # 2. Read the payload
            payload = b""
            if length > 0:
                payload = safe_recv(src_sock, length)
                if payload is None:
                    log(f"{src_name} disconnected while sending payload (expected {length} bytes).")
                    break
            
            # Print debug info (condensed)
            if length == 1:
                cmd = payload[0]
                cmd_name = {0: "Power Off", 1: "Power On", 2: "Reset", 4: "Get ATR"}.get(cmd, f"Control {cmd:02X}")
                log(f"[{src_name} -> {dst_name}] Control: {cmd_name}")
            else:
                log(f"[{src_name} -> {dst_name}] APDU: {payload.hex().upper()}")

            # 3. Forward the complete frame [Length] + [Payload]
            dst_sock.sendall(len_data + payload)
            
    except Exception as e:
        if not exit_event.is_set():
            log(f"Error in relay loop {src_name} -> {dst_name}: {e}")
    finally:
        exit_event.set()

def run_bridge(phone_ip, phone_port, vpcd_host, vpcd_port, server_mode):
    exit_event = threading.Event()
    
    phone_sock = None
    vpcd_sock = None

    try:
        # 1. Connect or listen for Phone
        if server_mode:
            # Server Mode: Listen on local port and wait for iPhone to connect
            server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server_sock.bind(("0.0.0.0", phone_port))
            server_sock.listen(1)
            log(f"Server Mode: Listening for iPhone connection on 0.0.0.0:{phone_port}...")
            phone_sock, phone_addr = server_sock.accept()
            log(f"iPhone connected from {phone_addr[0]}:{phone_addr[1]}")
            server_sock.close()
        else:
            # Client Mode: Connect directly to iPhone IP
            log(f"Client Mode: Connecting to iPhone at {phone_ip}:{phone_port}...")
            phone_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            while True:
                try:
                    phone_sock.connect((phone_ip, phone_port))
                    log("Connected to iPhone TCP Server successfully.")
                    break
                except socket.error as e:
                    log(f"Could not connect to iPhone: {e}. Retrying in 3 seconds...")
                    time.sleep(3)
        
        # 2. Connect to PC's vpcd driver (virtual reader)
        log(f"Connecting to vpcd on {vpcd_host}:{vpcd_port}...")
        vpcd_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        while True:
            try:
                vpcd_sock.connect((vpcd_host, vpcd_port))
                log("Connected to vpcd successfully.")
                break
            except socket.error as e:
                log(f"Could not connect to vpcd: {e}. Ensure PCSC-Lite/vpcd is running. Retrying in 3 seconds...")
                time.sleep(3)
        
        # 3. Spin up two threads for bi-directional relaying
        t1 = threading.Thread(target=relay_loop, args=(vpcd_sock, phone_sock, "PC/vpcd", "iPhone", exit_event), daemon=True)
        t2 = threading.Thread(target=relay_loop, args=(phone_sock, vpcd_sock, "iPhone", "PC/vpcd", exit_event), daemon=True)
        
        t1.start()
        t2.start()
        
        # Keep main thread alive until exit event is flagged
        while not exit_event.is_set():
            time.sleep(0.5)

    except KeyboardInterrupt:
        log("Shutting down bridge via keyboard interrupt.")
    except Exception as e:
        log(f"Bridge error: {e}")
    finally:
        exit_event.set()
        log("Closing sockets...")
        if phone_sock:
            try:
                phone_sock.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            phone_sock.close()
        if vpcd_sock:
            try:
                vpcd_sock.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            vpcd_sock.close()
        log("Bridge stopped.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="vsmartcard vpcd to iPhone NFC Relay Bridge")
    parser.add_argument("--phone-ip", type=str, help="IP Address of the iPhone running the Relay app (Client Mode)")
    parser.add_argument("--phone-port", type=int, default=DEFAULT_PHONE_PORT, help="Port of the iPhone TCP Server / Local listen port (Default: 35963)")
    parser.add_argument("--vpcd-host", type=str, default="127.0.0.1", help="Host running vpcd driver (Default: 127.0.0.1)")
    parser.add_argument("--vpcd-port", type=int, default=DEFAULT_VPCD_PORT, help="Port running vpcd driver (Default: 35963)")
    parser.add_argument("--server", action="store_true", help="Run in Server Mode (Wait for the iPhone to connect to the PC instead)")
    
    args = parser.parse_args()
    
    if not args.server and not args.phone_ip:
        parser.print_help()
        print("\n[!] Error: You must specify --phone-ip unless running in --server mode.")
        sys.exit(1)
        
    run_bridge(args.phone_ip, args.phone_port, args.vpcd_host, args.vpcd_port, args.server)
