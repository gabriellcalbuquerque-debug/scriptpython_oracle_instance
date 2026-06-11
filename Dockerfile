FROM python:3.11-slim

# Instala dependências
RUN pip install oci requests --quiet && \
    apt-get update && apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
COPY server.py /app/server.py
COPY retry_oci.py /app/retry_oci.py
RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/app/docker-entrypoint.sh"]
