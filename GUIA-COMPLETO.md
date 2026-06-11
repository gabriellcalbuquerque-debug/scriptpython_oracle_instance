# Guia Completo — OCI ARM Instance no Windows

Objetivo: subir uma VM.Standard.A1.Flex (4 OCPUs, 24GB RAM — free tier) na Oracle Cloud automaticamente, mesmo com o erro "Out of capacity".

---

## PRÉ-REQUISITOS

- Conta Oracle Cloud ativa (free tier serve)
- Windows 10/11
- PowerShell 5.1+ (já vem no Windows)

---

## PASSO 1 — Instalar o OCI CLI

Abra o **PowerShell como Administrador** e execute:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1 -OutFile install_oci.ps1
.\install_oci.ps1 --accept-all-defaults
```

Feche e reabra o PowerShell. Teste:

```powershell
oci --version
# Deve exibir: 3.x.x
```

---

## PASSO 2 — Criar a chave de API na OCI Console

1. Acesse: https://cloud.oracle.com → faça login
2. Clique no ícone de perfil (canto superior direito) → **"My profile"**
3. Menu esquerdo → **"API keys"** → botão **"Add API key"**
4. Selecione **"Generate API key pair"**
5. Clique **"Download private key"** → salve como `oci_api_key.pem`
6. Clique **"Add"**
7. Na tela de confirmação, copie o bloco de configuração que aparece — você vai precisar dele no próximo passo

O bloco tem este formato:
```
[DEFAULT]
user=ocid1.user.oc1..XXXX
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..XXXX
region=sa-saopaulo-1
key_file=<path_to_your_private_keyfile>
```

---

## PASSO 3 — Configurar o OCI CLI

Mova a chave privada para o local padrão:

```powershell
# Cria a pasta .oci se não existir
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.oci"

# Mova o arquivo oci_api_key.pem que você baixou
Move-Item -Path "$env:USERPROFILE\Downloads\oci_api_key.pem" -Destination "$env:USERPROFILE\.oci\oci_api_key.pem"
```

Crie o arquivo de config:

```powershell
notepad "$env:USERPROFILE\.oci\config"
```

Cole o bloco copiado no Passo 2 e ajuste `key_file`:

```ini
[DEFAULT]
user=ocid1.user.oc1..XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
region=sa-saopaulo-1
key_file=C:\Users\SEU_USUARIO\.oci\oci_api_key.pem
```

> ⚠️ Substitua `SEU_USUARIO` pelo seu nome de usuário do Windows.

Salve e teste:

```powershell
oci iam user get --user-id (oci iam user list --query 'data[0].id' --raw-output)
# Deve retornar dados do seu usuário
```

---

## PASSO 4 — Instalar o Terraform

1. Acesse: https://developer.hashicorp.com/terraform/install#windows
2. Baixe o ZIP para Windows (AMD64)
3. Extraia o arquivo `terraform.exe`
4. Mova para `C:\terraform\` (crie a pasta)
5. Adicione ao PATH:

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\terraform", [System.EnvironmentVariableTarget]::Machine)
```

6. Feche e reabra o PowerShell. Teste:

```powershell
terraform --version
# Deve exibir: Terraform v1.x.x
```

---

## PASSO 5 — Coletar os OCIDs necessários

Execute cada comando e anote o valor retornado:

### 5.1 — Tenancy OCID (já está no ~/.oci/config como `tenancy=`)

```powershell
oci iam tenancy get --tenancy-id (Get-Content "$env:USERPROFILE\.oci\config" | Select-String "tenancy=" | ForEach-Object { $_ -replace "tenancy=","" }) --query 'data.id' --raw-output
```

### 5.2 — Compartment OCID (root = mesmo que tenancy)

No free tier, use o OCID do tenancy como compartment. Para listar compartimentos:

```powershell
oci iam compartment list --query 'data[*].{name:name, id:id}' --output table
```

### 5.3 — Availability Domains disponíveis

```powershell
oci iam availability-domain list --query 'data[*].name' --output table
```

Exemplo de saída:
```
+---------------------------------+
| Column1                         |
+---------------------------------+
| iMvT:SA-SAOPAULO-1-AD-1         |
+---------------------------------+
```

### 5.4 — Imagem Ubuntu 22.04 ARM

```powershell
oci compute image list `
  --compartment-id SEU_TENANCY_OCID `
  --shape "VM.Standard.A1.Flex" `
  --operating-system "Canonical Ubuntu" `
  --operating-system-version "22.04" `
  --query 'data[0].id' --raw-output
```

### 5.5 — Subnet OCID

```powershell
oci network subnet list `
  --compartment-id SEU_TENANCY_OCID `
  --query 'data[*].{name:"display-name", id:id}' --output table
```

Se não tiver nenhuma subnet, você precisa criar uma VCN primeiro:
```powershell
oci network vcn create-default --compartment-id SEU_TENANCY_OCID --display-name "vcn-botchat"
```

---

## PASSO 6 — Gerar chave SSH

Se não tiver uma chave SSH:

```powershell
ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa" -N '""'
```

---

## PASSO 7 — Preencher o arquivo de variáveis

Na pasta `oci-arm-instance`, edite `terraform.tfvars.template` com os valores coletados:

```powershell
cd "C:\Users\SEU_USUARIO\Claude\Projects\BotChat Geek\oci-arm-instance"
notepad terraform.tfvars.template
```

Substitua todos os `ocid1.XXXX...` pelos seus valores reais.

Depois, edite o `retry.ps1` e confirme os ADs na variável `$AvailabilityDomains`.

---

## PASSO 8 — Rodar o script de retry

```powershell
cd "C:\Users\SEU_USUARIO\Claude\Projects\BotChat Geek\oci-arm-instance"
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
.\retry.ps1
```

O script vai:
- Tentar criar a instância a cada 60 segundos
- Rotar entre os ADs disponíveis
- Parar automaticamente ao ter sucesso
- Mostrar o IP público da instância criada
- Salvar tudo em `retry.log`

---

## PASSO 9 — Conectar na instância

Assim que o script tiver sucesso:

```powershell
ssh -i "$env:USERPROFILE\.ssh\id_rsa" ubuntu@IP_PUBLICO_AQUI
```

---

## PROBLEMAS COMUNS

| Erro | Solução |
|------|---------|
| `Out of capacity` | Normal — o script de retry cuida disso |
| `Service error: NotAuthenticated` | Verifique o `key_file` no `~/.oci/config` |
| `terraform: command not found` | Reinicie o PowerShell após adicionar ao PATH |
| `InvalidParameter: image not found` | Use o OCID correto da imagem ARM para sua região |
| Subnet não existe | Crie uma VCN com o comando do Passo 5.5 |

---

## ESTRUTURA DOS ARQUIVOS

```
oci-arm-instance/
├── main.tf                    # Configuração Terraform da instância
├── variables.tf               # Declaração das variáveis
├── terraform.tfvars.template  # Template — preencha com seus dados
├── retry.ps1                  # Script de retry (Windows PowerShell)
├── retry.sh                   # Script de retry (Linux/macOS)
├── .gitignore                 # Exclui arquivos sensíveis do git
└── GUIA-COMPLETO.md           # Este guia
```
