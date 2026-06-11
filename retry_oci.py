#!/usr/bin/env python3
"""Retry OCI ARM instance usando Python SDK com timeout controlado"""

import json
import os
import sys
import time
import base64
import requests
import subprocess
from datetime import datetime

# Configurações
AD             = ""
COMPARTMENT_ID = ""
SUBNET_ID      = ""
IMAGE_ID       = ""
SSH_KEY        = "ssh-rsa "
MAX_RPM        = 3          # máximo de requisições por minuto (único valor empiricamente seguro)
INTERVAL       = 20         # 20s — ótimo matematicamente: 4320 tentativas/dia sem nenhuma pausa de 429
LOG_FILE       = "/app/retry.log"
RESEND_API_KEY = os.environ.get("RESEND_API_KEY", "")
ALERT_EVERY    = 30  # alertas de status a cada X falhas

def log(msg):
    line = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def send_email(subject, html):
    if not RESEND_API_KEY:
        return
    try:
        requests.post(
            "https://api.resend.com/emails",
            headers={"Authorization": f"Bearer {RESEND_API_KEY}"},
            json={
                "from": "BotChat Geek <onboarding@resend.dev>",
                "to": [""],
                "subject": subject,
                "html": html
            },
            timeout=10
        )
    except Exception as e:
        log(f"Erro ao enviar email: {e}")

def try_launch():
    import oci
    config = oci.config.from_file("~/.oci/config")
    compute = oci.core.ComputeClient(config, timeout=(10, 30))

    details = oci.core.models.LaunchInstanceDetails(
        availability_domain=AD,
        compartment_id=COMPARTMENT_ID,
        shape="VM.Standard.A1.Flex",
        shape_config=oci.core.models.LaunchInstanceShapeConfigDetails(
            ocpus=4,
            memory_in_gbs=24
        ),
        source_details=oci.core.models.InstanceSourceViaImageDetails(
            image_id=IMAGE_ID
        ),
        create_vnic_details=oci.core.models.CreateVnicDetails(
            subnet_id=SUBNET_ID,
            assign_public_ip=True
        ),
        display_name="botchat-geek-arm",
        metadata={"ssh_authorized_keys": SSH_KEY}
    )

    response = compute.launch_instance(details)
    return response.data

def get_public_ip(instance_id):
    import oci
    config = oci.config.from_file("~/.oci/config")
    compute = oci.core.ComputeClient(config, timeout=(10, 30))
    network = oci.core.VirtualNetworkClient(config, timeout=(10, 30))

    for _ in range(12):  # tenta por 2 minutos
        time.sleep(10)
        try:
            vnics = compute.list_vnic_attachments(COMPARTMENT_ID, instance_id=instance_id).data
            if vnics:
                vnic = network.get_vnic(vnics[0].vnic_id).data
                if vnic.public_ip:
                    return vnic.public_ip
        except Exception:
            pass
    return "verifique o console OCI"

def main():
    try:
        import oci
    except ImportError:
        log("Instalando OCI SDK...")
        subprocess.run([sys.executable, "-m", "pip", "install", "oci", "-q"], check=True)
        import oci

    log(f"=== Iniciando retry loop (intervalo: {INTERVAL}s) ===")
    attempt = 0
    consecutive_failures = 0

    while True:
        attempt += 1
        log(f"--- Tentativa #{attempt} | AD: {AD} ---")

        try:
            instance = try_launch()
            log(f"✅ SUCESSO! Instância criada: {instance.id}")
            log(f"Estado: {instance.lifecycle_state}")

            public_ip = get_public_ip(instance.id)
            log(f"IP Público: {public_ip}")

            send_email(
                "✅ Instância OCI ARM criada!",
                f"<h2>Sua instância OCI ARM foi criada!</h2>"
                f"<p><strong>IP:</strong> {public_ip}</p>"
                f"<p><strong>Shape:</strong> VM.Standard.A1.Flex (4 OCPUs, 24GB)</p>"
                f"<p><code>ssh -i ~/.ssh/id_rsa ubuntu@{public_ip}</code></p>"
            )

            log("Mantendo container ativo...")
            while True:
                time.sleep(3600)

        except Exception as e:
            err = str(e)
            consecutive_failures += 1

            if "Out of host capacity" in err or "InternalError" in err or "500" in err:
                log(f"Sem capacidade. Tentativa {attempt}. Próxima em {INTERVAL}s...")
            elif "429" in err or "TooManyRequests" in err:
                log(f"Rate limit atingido. Aguardando 180s para resetar janela da OCI...")
                time.sleep(180)
                continue
            elif "NotAuthenticated" in err or "InvalidParameter" in err or "403" in err:
                log(f"ERRO CRÍTICO: {err[:200]}")
                send_email("🚨 Erro crítico OCI", f"<pre>{err[:500]}</pre>")
                sys.exit(1)
            else:
                log(f"Erro ({attempt}): {err[:150]}")

            if consecutive_failures % ALERT_EVERY == 0:
                send_email(
                    "⚠️ BotChat Geek — Retry ativo",
                    f"<p>{attempt} tentativas sem sucesso. Script rodando normalmente.</p>"
                    f"<p><a href='https://botchat-geek-oci-retry.fly.dev'>Ver dashboard</a></p>"
                )
                consecutive_failures = 0

            time.sleep(INTERVAL)

if __name__ == "__main__":
    main()
