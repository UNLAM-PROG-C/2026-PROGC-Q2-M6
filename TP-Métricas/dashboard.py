"""Small standard-library HTTP dashboard for the live simulation."""

from __future__ import annotations

import json
import logging
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


LOGGER = logging.getLogger("airline.dashboard")


HTML = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Airline simulator</title>
<style>body{font:14px system-ui;background:#101820;color:#e8f0f2;margin:24px}
table{border-collapse:collapse;width:100%;margin:12px 0}td,th{border:1px solid #40515b;padding:6px;text-align:left}
.card{background:#172631;padding:14px;border-radius:8px;margin-bottom:16px}
pre{max-height:360px;overflow:auto;white-space:pre-wrap}</style></head>
<body><h1>Airline simulator</h1><div class="card" id="summary">Loading...</div>
<div class="card"><h2>Fleet</h2><table id="fleet"><thead><tr><th>ID</th><th>Status</th><th>Airport</th><th>Flight</th></tr></thead><tbody></tbody></table></div>
<div class="card"><h2>Flights</h2><table id="flights"><thead><tr><th>ID</th><th>Priority</th><th>Status</th><th>Route</th><th>Plane</th></tr></thead><tbody></tbody></table></div>
<div class="card"><h2>Operations</h2><pre id="operations"></pre></div>
<script>
const esc=s=>String(s??'').replaceAll('&','&amp;').replaceAll('<','&lt;');
async function refresh(){const d=await fetch('/api/state').then(r=>r.json());
document.querySelector('#summary').textContent=`Simulated minutes: ${d.simulated_minutes.toFixed(1)} | planes: ${d.planes.length} | flights: ${d.flights.length}`;
document.querySelector('#fleet tbody').innerHTML=d.planes.map(p=>`<tr><td>${esc(p.id)}</td><td>${esc(p.status)}</td><td>${esc(p.airport)}</td><td>${esc(p.flight)}</td></tr>`).join('');
document.querySelector('#flights tbody').innerHTML=d.flights.map(f=>`<tr><td>${esc(f.id)}</td><td>${esc(f.priority)}</td><td>${esc(f.status)}</td><td>${esc(f.origin)} → ${esc(f.destination)}</td><td>${esc(f.plane)}</td></tr>`).join('');
document.querySelector('#operations').textContent=d.operations.join('\\n');}
refresh();setInterval(refresh,1000);
</script></body></html>"""


class DashboardHandler(BaseHTTPRequestHandler):
  state = None

  def do_GET(self):
    if self.path == "/api/state":
      self._send_json(self.state.snapshot())
    else:
      self._send(200, "text/html", HTML)

  def _send_json(self, payload):
    self._send(200, "application/json", json.dumps(payload))

  def _send(self, code, content_type, body):
    data = body.encode("utf-8")
    self.send_response(code)
    self.send_header("Content-Type", f"{content_type}; charset=utf-8")
    self.send_header("Content-Length", str(len(data)))
    self.end_headers()
    self.wfile.write(data)

  def log_message(self, format, *args):
    return


def make_handler(state):
  DashboardHandler.state = state
  return DashboardHandler


class DashboardServer(threading.Thread):
  def __init__(self, state, host, port):
    super().__init__(name="dashboard-server")
    self.server = ThreadingHTTPServer((host, port), make_handler(state))
    self.daemon = True

  @property
  def address(self):
    return self.server.server_address

  def run(self):
    self.server.serve_forever(poll_interval=0.2)

  def close(self):
    self.server.shutdown()
    self.server.server_close()
