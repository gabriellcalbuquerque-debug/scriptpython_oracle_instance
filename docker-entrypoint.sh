#!/bin/bash
set -euo pipefail

INTERVAL=10
LOG_FILE="/app/retry.log"
AD="gabm:SA-SAOPAULO-1-AD-1"
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaalysxw323jmagtrmmy74xxpy4ax4bgvxfhwbymrlhlybupzkh6c7q"
SUBNET_ID="ocid1.subnet.oc1.sa-saopaulo-1.aaaaaaaa5abbhnrups43yrwfjpsfkro4fdrxv57w7jeexlt7r7ivctlvzkoq"
IMAGE_ID="ocid1.image.oc1.sa-saopaulo-1.aaaaaaaal2igd4tgw4xlhdk3euqett5c6fvidgutkigumpbnote4ovpgylsq"
SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDUKhfygOrmtgxMm04O1IjvNNSZb/x+9oFZ49MYjZS/t7PAcJ3X7/X/p/WV++ZlC5h2vf8Oai2nnmSdyLI3AvrEK4PY82Y5IVOGgUOgn3r2Nd+rYHElamYSVn8x7J/GqjtNFEyszU0enq5h12d39jq2cUZF/YZw9ghf9Sdc/V//VZSsKalnH8Fxri0vmnOkzUWkNoB6jjD6Gm1NPTKJkUcJH1ljJmeExYIz6kGuQRwAlxdX8dcXcGJVIphRovVISMMCdgZgICFz/7IXvPJa0YEQ+MwlnrYb5IHKPqG/Qw0490KZjvMG0VNKsNjhFd9Ox/dzJ262gcHQbI+rb/y0TBZk5x4Z5a1VdMexNe+q3/sjDlMAlqpZigo7BcmtUqnnSZZddId5sjib7DhGBkVZAtnVuzPktsmJLYkeu0mrJQamiZvBUW8gqV6WyMhP4fej4of/GIp4SeeZGzKoDLbwpGxgSmxTCv9iPTrL2vhj+12l6nA5VDfbttKAF2Lhegg+7QvpMeaWXp8CD+m1ujHfcNCLawXsOtf1smgxGxutEXgu/SmcciS97gir6CVY/GXzdknoNVoCsevQKnvd4hrNBljZL8HEny4vUXgf7K12wQqnU4Jdz0KG0pfyaDWQeiVySkK7x3W3v7d61MDHzUTy3gViJKjNDMwWYgbu12WEP3lh9Q== biel_@Gabriel-PC"
ALERT_AFTER_FAILURES=30
CONSECUTIVE_FAILURES=0

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

send_email() {
  local subject="$1"
  local body="$2"
  if [[ -n "${RESEND_API_KEY:-}" ]]; then
    curl -s -X POST https://api.resend.com/emails \
      -H "Authorization: Bearer $RESEND_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"from\": \"BotChat Geek <onboarding@resend.dev>\",
        \"to\": [\"gabriel.lcalbuquerque@gmail.com\"],
        \"subject\": \"$subject\",
        \"html\": \"$body\"
      }" > /dev/null
  fi
}

# --- Configura OCI credentials ---
log "Configurando credenciais OCI..."
mkdir -p ~/.oci

echo "$OCI_CONFIG_B64"      | base64 -d > ~/.oci/config
echo "$OCI_PRIVATE_KEY_B64" | base64 -d > ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/oci_api_key.pem
chmod 600 ~/.oci/config
sed -i 's|key_file=.*|key_file=/root/.oci/oci_api_key.pem|' ~/.oci/config

# Inicia dashboard web em background
python3 /app/server.py &
log "Dashboard disponível em https://botchat-geek-oci-retry.fly.dev"
log "Credenciais configuradas. Testando conectividade..."

# Teste IAM
CONN_IAM=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://identity.sa-saopaulo-1.oraclecloud.com || echo "FAIL")
log "IAM endpoint: $CONN_IAM"

# Teste Compute
CONN_COMPUTE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://iaas.sa-saopaulo-1.oraclecloud.com/20160918/instances || echo "FAIL")
log "Compute endpoint: $CONN_COMPUTE"

log "Iniciando retry com Python OCI SDK..."

# Usa Python SDK em vez de OCI CLI
exec python3 /app/retry_oci.py

# --- Loop de retry com OCI CLI (fallback) ---
log "=== Iniciando retry loop (intervalo: ${INTERVAL}s) ==="
attempt=0

while true; do
  attempt=$((attempt + 1))
  log "--- Tentativa #$attempt | AD: $AD ---"

  RESULT=$(timeout 60 oci compute instance launch \
    --availability-domain "$AD" \
    --compartment-id "$COMPARTMENT_ID" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config '{"ocpus": 4, "memoryInGBs": 24}' \
    --image-id "$IMAGE_ID" \
    --subnet-id "$SUBNET_ID" \
    --display-name "botchat-geek-arm" \
    --assign-public-ip true \
    --metadata "{\"ssh_authorized_keys\": \"$SSH_KEY\"}" \
    2>&1 || echo "TIMEOUT_OR_ERROR")

  log "Resposta OCI: ${RESULT:0:150}"

  if echo "$RESULT" | grep -q '"lifecycle-state": "PROVISIONING"\|"lifecycle-state": "RUNNING"'; then
    PUBLIC_IP=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('public-ip','pendente'))" 2>/dev/null || echo "pendente")
    INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('id',''))" 2>/dev/null || echo "")

    log "✅ SUCESSO! Instância criada! ID: $INSTANCE_ID"

    # Aguarda IP público se ainda pendente
    if [[ "$PUBLIC_IP" == "pendente" || "$PUBLIC_IP" == "null" ]]; then
      log "Aguardando IP público..."
      sleep 30
      PUBLIC_IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" --compartment-id "$COMPARTMENT_ID" \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',[{}])[0].get('public-ip',''))" 2>/dev/null || echo "verifique o console OCI")
    fi

    log "IP Público: $PUBLIC_IP"

    send_email \
      "✅ Instância OCI ARM criada!" \
      "<h2>Sua instância OCI ARM foi criada com sucesso!</h2><p><strong>IP Público:</strong> $PUBLIC_IP</p><p><strong>Nome:</strong> botchat-geek-arm</p><p><strong>Shape:</strong> VM.Standard.A1.Flex (4 OCPUs, 24GB RAM)</p><p>Conecte via SSH:<br><code>ssh -i ~/.ssh/id_rsa ubuntu@$PUBLIC_IP</code></p>"

    log "Email enviado! Container mantido ativo."
    sleep infinity

  elif echo "$RESULT" | grep -q "Out of host capacity\|out of host capacity\|InternalError"; then
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    log "Sem capacidade. Tentando em ${INTERVAL}s... (tentativa: $attempt)"

  elif echo "$RESULT" | grep -q "NotAuthenticated\|InvalidParameter\|Forbidden"; then
    log "ERRO CRÍTICO: $RESULT"
    send_email \
      "🚨 BotChat Geek — Erro crítico no retry OCI" \
      "<h2>Erro crítico!</h2><p>O script parou por erro de autenticação ou configuração.</p><pre>${RESULT:0:500}</pre>"
    exit 1

  else
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    log "Resposta inesperada (tentativa $attempt): ${RESULT:0:200}"
  fi

  # Alerta de travamento
  if [[ $CONSECUTIVE_FAILURES -eq $ALERT_AFTER_FAILURES ]]; then
    log "⚠️ Enviando alerta de status..."
    send_email \
      "⚠️ BotChat Geek — Retry ativo, sem capacidade ainda" \
      "<h2>Status do retry</h2><p>Já foram <strong>$attempt tentativas</strong> sem sucesso.</p><p>O script continua rodando normalmente — só não há capacidade disponível ainda na Oracle.</p><p><a href='https://fly.io/apps/botchat-geek-oci-retry/monitoring'>Ver logs ao vivo</a></p>"
    CONSECUTIVE_FAILURES=0
  fi

  sleep "$INTERVAL"
done
