import os
import hashlib
import tempfile
from datetime import datetime
import backup 

def test_file_hash_same_content(tmp_path):
    """Test: același fișier trebuie să aibă același hash"""
    file_path = tmp_path / "file.txt"
    file_path.write_text("test123")
    
    hash1 = backup.file_hash(file_path)
    hash2 = backup.file_hash(file_path)
    
    assert hash1 == hash2, "Hash-ul trebuie să fie același pentru același conținut"

def test_file_hash_different_files(tmp_path):
    """Test: fișiere diferite -> hash diferit"""
    file1 = tmp_path / "f1.txt"
    file2 = tmp_path / "f2.txt"
    file1.write_text("abc")
    file2.write_text("xyz")

    h1 = backup.file_hash(file1)
    h2 = backup.file_hash(file2)
    
    assert h1 != h2, "Hash-urile trebuie să fie diferite pentru conținut diferit"

def test_log_error_creates_file(tmp_path):
    """Test: funcția log_error scrie mesajul în fișier"""
    test_log = tmp_path / "error.log"
    backup.error_log_file = test_log  # redirecționăm logul către un fișier temporar
    
    backup.log_error("Mesaj de test")
    
    assert test_log.exists(), "Fișierul de log ar trebui să fie creat"
    content = test_log.read_text()
    assert "Mesaj de test" in content, "Mesajul de eroare trebuie scris în fișier"

def test_backup_dir_created(tmp_path):
    """Test: verifică dacă directorul de backup este creat"""
    test_dir = tmp_path / "mybackup"
    if test_dir.exists():
        os.rmdir(test_dir)
    os.environ["BACKUP_DIR"] = str(test_dir)
    
    os.makedirs(test_dir, exist_ok=True)
    
    assert os.path.exists(test_dir), "Directorul de backup ar trebui să fie creat"
