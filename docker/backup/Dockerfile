FROM python:3.11-slim

WORKDIR /app

COPY ../../scripts/backup.py /app/backup.py

RUN mkdir -p /data/backup

ENV BACKUP_INTERVAL=30
ENV BACKUP_DIR=/data/backup

CMD ["python3", "backup.py"]
