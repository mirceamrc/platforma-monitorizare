# Script Python pentru efectuarea backup-ului logurilor de sistem.
import os
import time
import shutil
import hashlib
from datetime import datetime

source_file = "/data/system-state.log"

backup_interval = int(os.getenv("BACKUP_INTERVAL", "30"))

backup_dir = os.getenv("BACKUP_DIR", "./backup")

error_log_file = "/data/error.log"

os.makedirs(backup_dir, exist_ok=True)

def log_error(message):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"{timestamp} [EROARE] {message}\n"
    print(message)
    try:
        with open(error_log_file, "a") as f:
            f.write(log_message)
    except Exception as e:
        print(f"Nu s-a putut scrie in fisierul de log: {e}")

# Creăm directorul de backup dacă nu există
if not os.path.exists(backup_dir):
    try:
        os.makedirs(backup_dir)
        print(f"Directorul '{backup_dir}' a fost creat.")
    except Exception as e:
        log_error(f"Eroare la crearea directorului '{backup_dir}': {e}")

# Variabilă pentru a reține ultimul hash al fișierului
last_hash = None

def file_hash(file_path):
    try:
        with open(file_path, "rb") as f:
            file_content = f.read()
            return hashlib.sha256(file_content).hexdigest()
    except Exception as e:
        log_error(f"Eroare la calcularea hash-ului fisierului '{file_path}': {e}")
        return None

if __name__ == "__main__":

    print(f"Pornim monitorizarea fisierului '{source_file}' cu intervalul de {backup_interval} secunde.")

    while True:
        try:
            if os.path.exists(source_file):
                current_hash = file_hash(source_file)

                if current_hash is None:
                    print("Nu s-a putut calcula hashul fisierului. Se sare peste backup.")
                elif last_hash != current_hash:
                    last_hash = current_hash

                    # Creăm numele fișierului de backup cu data și ora curentă
                    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                    backup_file = os.path.join(backup_dir, f"system-state_{timestamp}.log")

                    try:
                        shutil.copy(source_file, backup_file)
                        print(f"Backup realizat: {backup_file}")
                    except Exception as e:
                        log_error(f"Eroare la copierea fisierului: {e}")
                else:
                    print("Fisierul nu s-a modificat. Nu se facem backup.")
            else:
                print(f"Fisierul '{source_file}' nu exista.")
        except Exception as e:
            log_error(f"Eroare: {e}")

        time.sleep(backup_interval)
