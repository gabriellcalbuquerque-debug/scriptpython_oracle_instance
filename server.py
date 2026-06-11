#!/usr/bin/env python3
"""Dashboard ao vivo para o retry OCI ARM"""

import http.server
import json
import os
import threading
import time
from datetime import datetime

LOG_FILE = "/app/retry.log"
STATS_FILE = "/app/stats.json"

HTML = """<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BotChat Geek — OCI Retry</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0d1117; color: #c9d1d9; font-family: 'Segoe UI', monospace; }
    header { background: #161b22; border-bottom: 1px solid #30363d; padding: 16px 24px; display: flex; align-items: center; gap: 12px; }
    header h1 { font-size: 18px; color: #58a6ff; }
    header .dot { width: 10px; height: 10px; border-radius: 50%; background: #3fb950; animation: pulse 1.5s infinite; }
    @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.3} }
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px; padding: 24px; }
    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
    .card .label { font-size: 12px; color: #8b949e; text-transform: uppercase; letter-spacing: 1px; }
    .card .value { font-size: 28px; font-weight: bold; color: #58a6ff; margin-top: 4px; }
    .card .value.success { color: #3fb950; }
    .card .value.error { color: #f85149; }
    .logs-container { margin: 0 24px 24px; background: #161b22; border: 1px solid #30363d; border-radius: 8px; overflow: hidden; }
    .logs-header { padding: 10px 16px; background: #21262d; font-size: 13px; color: #8b949e; display: flex; justify-content: space-between; align-items: center; }
    .logs-header span { color: #3fb950; font-size: 12px; }
    .logs { height: 500px; overflow-y: auto; padding: 12px 16px; font-size: 13px; line-height: 1.6; }
    .log-line { padding: 2px 0; border-bottom: 1px solid #0d1117; }
    .log-line.success { color: #3fb950; }
    .log-line.error { color: #f85149; }
    .log-line.warn { color: #d29922; }
    .log-line.info { color: #c9d1d9; }
    .log-line .time { color: #8b949e; margin-right: 8px; }
    .status-bar { background: #161b22; border-top: 1px solid #30363d; padding: 8px 24px; font-size: 12px; color: #8b949e; display: flex; gap: 16px; }
  </style>
</head>
<body>
  <header>
    <div class="dot" id="statusDot"></div>
    <h1>🤖 BotChat Geek — OCI ARM Retry</h1>
    <span style="margin-left:auto;font-size:13px;color:#8b949e" id="lastUpdate">--</span>
  </header>

  <div class="cards">
    <div class="card">
      <div class="label">Tentativas</div>
      <div class="value" id="attempts">0</div>
    </div>
    <div class="card">
      <div class="label">Status</div>
      <div class="value" id="status" style="font-size:16px;margin-top:8px">Aguardando...</div>
    </div>
    <div class="card">
      <div class="label">Sem Capacidade</div>
      <div class="value error" id="noCapacity">0</div>
    </div>
    <div class="card">
      <div class="label">Uptime</div>
      <div class="value" id="uptime" style="font-size:20px">--</div>
    </div>
  </div>

  <div class="logs-container">
    <div class="logs-header">
      <span>📋 Logs ao vivo</span>
      <span id="liveIndicator">● LIVE</span>
    </div>
    <div class="logs" id="logsDiv"></div>
  </div>

  <div class="status-bar">
    <span>Região: SA-SAOPAULO-1-AD-1</span>
    <span>Shape: VM.Standard.A1.Flex (4 OCPUs / 24GB)</span>
    <span>Intervalo: 20s (3 req/min)</span>
  </div>

  <script>
    const logsDiv = document.getElementById('logsDiv');
    let startTime = Date.now();
    let attempts = 0, noCapacity = 0;

    function classifyLine(line) {
      if (line.includes('SUCESSO') || line.includes('criada')) return 'success';
      if (line.includes('ERRO') || line.includes('Error') || line.includes('error')) return 'error';
      if (line.includes('Sem capacidade') || line.includes('Out of')) return 'warn';
      return 'info';
    }

    function addLog(line) {
      if (!line.trim()) return;
      const div = document.createElement('div');
      div.className = 'log-line ' + classifyLine(line);
      div.textContent = line;
      logsDiv.appendChild(div);
      logsDiv.scrollTop = logsDiv.scrollHeight;

      // Limita linhas no DOM
      while (logsDiv.children.length > 500) logsDiv.removeChild(logsDiv.firstChild);

      // Atualiza stats
      const m = line.match(/Tentativa #(\\d+)/);
      if (m) { attempts = parseInt(m[1]); document.getElementById('attempts').textContent = attempts; }
      if (line.includes('Sem capacidade') || line.includes('Out of')) {
        noCapacity++; document.getElementById('noCapacity').textContent = noCapacity;
        document.getElementById('status').textContent = '⏳ Sem capacidade';
        document.getElementById('status').style.color = '#d29922';
      }
      if (line.includes('SUCESSO')) {
        document.getElementById('status').textContent = '✅ Criada!';
        document.getElementById('status').style.color = '#3fb950';
        document.getElementById('statusDot').style.background = '#3fb950';
      }
      if (line.includes('Tentativa')) {
        document.getElementById('status').textContent = '🔄 Tentando...';
        document.getElementById('status').style.color = '#58a6ff';
      }

      document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString('pt-BR');
    }

    // Uptime counter
    setInterval(() => {
      const s = Math.floor((Date.now() - startTime) / 1000);
      const h = Math.floor(s/3600), m = Math.floor((s%3600)/60), sec = s%60;
      document.getElementById('uptime').textContent = `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(sec).padStart(2,'0')}`;
    }, 1000);

    // SSE para logs ao vivo
    const evtSource = new EventSource('/logs/stream');
    evtSource.onmessage = e => addLog(e.data);
    evtSource.onerror = () => {
      document.getElementById('liveIndicator').textContent = '○ RECONNECTING';
      document.getElementById('liveIndicator').style.color = '#d29922';
    };
    evtSource.onopen = () => {
      document.getElementById('liveIndicator').textContent = '● LIVE';
      document.getElementById('liveIndicator').style.color = '#3fb950';
    };
  </script>
</body>
</html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Silencia logs do servidor

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(HTML.encode())

        elif self.path == '/logs/stream':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()

            # Envia últimas 100 linhas primeiro
            if os.path.exists(LOG_FILE):
                with open(LOG_FILE, 'r') as f:
                    lines = f.readlines()[-100:]
                for line in lines:
                    try:
                        self.wfile.write(f"data: {line.rstrip()}\n\n".encode())
                    except BrokenPipeError:
                        return
                self.wfile.flush()

            # Fica transmitindo novas linhas
            with open(LOG_FILE, 'a+') as f:
                f.seek(0, 2)  # vai para o fim
                while True:
                    line = f.readline()
                    if line:
                        try:
                            self.wfile.write(f"data: {line.rstrip()}\n\n".encode())
                            self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            return
                    else:
                        time.sleep(0.5)

        elif self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'ok')

        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    os.makedirs('/app', exist_ok=True)
    if not os.path.exists(LOG_FILE):
        open(LOG_FILE, 'w').close()

    server = http.server.ThreadingHTTPServer(('0.0.0.0', 8080), Handler)
    print(f"Dashboard rodando em http://0.0.0.0:8080")
    server.serve_forever()
