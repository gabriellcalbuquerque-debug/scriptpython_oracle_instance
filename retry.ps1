# ============================================================
# retry.ps1 — Tenta criar instância OCI ARM em loop (Windows)
# Execução: .\retry.ps1
# ============================================================

$ErrorActionPreference = "Continue"

# --- Configuração ---
$IntervalSeconds = 60       # Intervalo entre tentativas
$MaxAttempts     = 0        # 0 = infinito
$LogFile         = "retry.log"

# ADs para tentar em rotação
# Execute: oci iam availability-domain list --query 'data[*].name'
$AvailabilityDomains = @(
    "gabm:SA-SAOPAULO-1-AD-1"
)

# --- Funções ---
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Show-Notification {
    param([string]$Title, [string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $notification = New-Object System.Windows.Forms.NotifyIcon
        $notification.Icon = [System.Drawing.SystemIcons]::Information
        $notification.BalloonTipTitle = $Title
        $notification.BalloonTipText = $Message
        $notification.Visible = $true
        $notification.ShowBalloonTip(5000)
        Start-Sleep -Seconds 2
        $notification.Dispose()
    } catch {
        # Silencioso se falhar
    }
}

function Invoke-TerraformCreate {
    param([string]$AD)

    Write-Log "Tentando AD: $AD"

    # Gera terraform.tfvars.current substituindo o placeholder
    $template = Get-Content "terraform.tfvars.template" -Raw
    $current  = $template -replace "__AD_PLACEHOLDER__", $AD
    Set-Content -Path "terraform.tfvars.current" -Value $current

    # Inicializa Terraform se necessário
    if (-not (Test-Path ".terraform")) {
        Write-Log "Inicializando Terraform..."
        terraform init -upgrade
        if ($LASTEXITCODE -ne 0) {
            Write-Log "ERRO: Falha ao inicializar Terraform."
            return $false
        }
    }

    # Destrói estado anterior com falha (se houver)
    Write-Log "Limpando estado anterior..."
    terraform destroy -auto-approve `
        -var-file="terraform.tfvars.current" `
        -target="oci_core_instance.arm_instance" 2>&1 | Out-Null

    # Tenta criar a instância
    Write-Log "Executando terraform apply..."
    $output = terraform apply -auto-approve `
        -var-file="terraform.tfvars.current" `
        -target="oci_core_instance.arm_instance" 2>&1

    # Salva output no log
    $output | Add-Content -Path $LogFile

    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    # Detecta tipo de erro
    $outputStr = $output -join "`n"
    if ($outputStr -match "Out of capacity|out of host capacity|InternalError") {
        Write-Log "Sem capacidade disponivel no AD: $AD"
    } elseif ($outputStr -match "LimitExceeded") {
        Write-Log "ERRO: Limite de recursos atingido. Verifique sua conta Oracle."
        return $false
    } elseif ($outputStr -match "NotAuthenticated|AuthenticationFailed") {
        Write-Log "ERRO: Falha de autenticação. Verifique seu ~/.oci/config"
        return $false
    } else {
        Write-Log "Erro desconhecido. Verifique retry.log para detalhes."
    }

    return $false
}

# --- Main ---
Write-Log "=== Iniciando retry loop para OCI ARM (VM.Standard.A1.Flex) ==="
Write-Log "Intervalo: ${IntervalSeconds}s | Max tentativas: $(if ($MaxAttempts -eq 0) { 'infinito' } else { $MaxAttempts })"
Write-Log "ADs configurados: $($AvailabilityDomains -join ', ')"

# Verifica dependências
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Log "ERRO: Terraform nao encontrado. Instale e adicione ao PATH."
    exit 1
}
if (-not (Get-Command oci -ErrorAction SilentlyContinue)) {
    Write-Log "AVISO: OCI CLI nao encontrado. O Terraform usa ~/.oci/config diretamente."
}
if (-not (Test-Path "terraform.tfvars.template")) {
    Write-Log "ERRO: terraform.tfvars.template nao encontrado. Execute na pasta oci-arm-instance."
    exit 1
}

$attempt  = 0
$adCount  = $AvailabilityDomains.Count

while ($true) {
    $attempt++

    if ($MaxAttempts -gt 0 -and $attempt -gt $MaxAttempts) {
        Write-Log "ERRO: Numero maximo de tentativas ($MaxAttempts) atingido."
        exit 1
    }

    $adIndex  = ($attempt - 1) % $adCount
    $currentAD = $AvailabilityDomains[$adIndex]

    Write-Log "--- Tentativa #$attempt | AD: $currentAD ---"

    $success = Invoke-TerraformCreate -AD $currentAD

    if ($success) {
        Write-Log "SUCESSO! Instancia criada no AD: $currentAD"
        Write-Log "--- Outputs ---"
        terraform output | Tee-Object -Append -FilePath $LogFile
        Show-Notification -Title "BotChat Geek" -Message "Instância OCI criada com sucesso!"
        Write-Host "`n✅ Pronto! Conecte via SSH com o IP acima." -ForegroundColor Green
        exit 0
    }

    Write-Log "Aguardando ${IntervalSeconds}s antes da proxima tentativa..."
    Start-Sleep -Seconds $IntervalSeconds
}
