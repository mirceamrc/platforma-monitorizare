FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    procps \
    sysstat \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY scripts/monitoring.sh /app/monitoring.sh

RUN chmod +x /app/monitoring.sh

ENV INTERVAL=30

CMD ["./monitoring.sh"]

