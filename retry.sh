#!/bin/bash
# ============================================================
# retry.sh — Tenta criar a instância OCI ARM em loop
# até encontrar capacidade disponível
# ============================================================

set -euo pipefail

# --- Configuração ---
INTERVAL_SECONDS=60       # Intervalo entre tentativas (segundos)
MAX_ATTEMPTS=0            # 0 = infinito
LOG_FILE="retry.log"

# ADs para tentar em rotação (ajuste conforme sua região)
# Para listar os ADs disponíveis: oci iam availability-domain list
AVAILABILITY_DOMAINS=(
  "iMvT:SA-SAOPAULO-1-AD-1"
  # Adicione mais ADs se sua região tiver:
  # "iMvT:SA-SAOPAULO-1-AD-2"
  # "iMvT:SA-SAOPAULO-1-AD-3"
)

# Notificação sonora ao conseguir (macOS/Linux)
NOTIFY_ON_SUCCESS=true

# --- Funções ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

notify_success() {
  if [[ "$NOTIFY_ON_SUCCESS" == "true" ]]; then
    # macOS
    command -v osascript &>/dev/null && \
      osascript -e 'display notification "Instância OCI criada com sucesso!" with title "BotChat Geek"' 2>/dev/null || true
    # Linux (requer libnotify)
    command -v notify-send &>/dev/null && \
      notify-send "BotChat Geek" "Instância OCI criada com sucesso!" 2>/dev/null || true
    # Som de terminal
    printf '\a'
  fi
}

try_create() {
  local ad="$1"
  log "Tentando AD: $ad"

  # Substitui o availability_domain no tfvars temporário
  sed "s|__AD_PLACEHOLDER__|$ad|g" terraform.tfvars.template > terraform.tfvars.current

  # Inicializa se necessário
  if [[ ! -d ".terraform" ]]; then
    log "Inicializando Terraform..."
    terraform init -upgrade
  fi

  # Destrói instância anterior com falha (se houver)
  terraform destroy -auto-approve \
    -var-file="terraform.tfvars.current" \
    -target="oci_core_instance.arm_instance" 2>/dev/null || true

  # Tenta criar
  if terraform apply -auto-approve \
    -var-file="terraform.tfvars.current" \
    -target="oci_core_instance.arm_instance" 2>&1 | tee -a "$LOG_FILE"; then
    return 0
  else
    return 1
  fi
}

# --- Main ---
log "=== Iniciando retry loop para OCI ARM (VM.Standard.A1.Flex) ==="
log "Intervalo: ${INTERVAL_SECONDS}s | Max tentativas: ${MAX_ATTEMPTS:-infinito}"

attempt=0
ad_count=${#AVAILABILITY_DOMAINS[@]}

while true; do
  attempt=$((attempt + 1))

  if [[ "$MAX_ATTEMPTS" -gt 0 && "$attempt" -gt "$MAX_ATTEMPTS" ]]; then
    log "ERRO: Número máximo de tentativas ($MAX_ATTEMPTS) atingido."
    exit 1
  fi

  # Rotaciona entre ADs disponíveis
  ad_index=$(( (attempt - 1) % ad_count ))
  current_ad="${AVAILABILITY_DOMAINS[$ad_index]}"

  log "--- Tentativa #$attempt | AD: $current_ad ---"

  if try_create "$current_ad"; then
    log "✅ SUCESSO! Instância criada no AD: $current_ad"
    terraform output | tee -a "$LOG_FILE"
    notify_success
    exit 0
  else
    # Verifica se é erro de capacidade ou outro erro
    if grep -q "Out of capacity\|out of host capacity\|InternalError\|LimitExceeded" "$LOG_FILE" 2>/dev/null; then
      log "⚠️  Sem capacidade. Aguardando ${INTERVAL_SECONDS}s antes da próxima tentativa..."
    else
      log "⚠️  Erro desconhecido. Aguardando ${INTERVAL_SECONDS}s..."
    fi
    sleep "$INTERVAL_SECONDS"
  fi
done
