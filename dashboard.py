#!/usr/bin/env python3
import html, subprocess, urllib.request
from http.server import BaseHTTPRequestHandler,HTTPServer
from datetime import datetime
HOST,PORT="127.0.0.1",8787
def run(c):
 try:return (subprocess.run(c,capture_output=True,text=True,timeout=10).stdout+subprocess.run(c,capture_output=True,text=True,timeout=10).stderr).strip()
 except Exception as e:return str(e)
def fetch(u):
 try:
  with urllib.request.urlopen(u,timeout=6) as r:return r.read(2000).decode("utf-8","replace")
 except Exception as e:return "Unavailable: "+str(e)
def data():
 return [("IPv4 country",fetch("https://ipinfo.io/country")),("IPv4 details",fetch("https://ipinfo.io/json")),("Timer enabled",run(["systemctl","is-enabled","google-region-force-nl-guardian.timer"])),("Timer active",run(["systemctl","is-active","google-region-force-nl-guardian.timer"])),("Timer schedule",run(["systemctl","list-timers","google-region-force-nl-guardian.timer","--no-pager"])),("Guardian service",run(["systemctl","status","google-region-force-nl-guardian.service","--no-pager"])),("IPv6 sysctl",run(["sysctl","net.ipv6.conf.all.disable_ipv6","net.ipv6.conf.default.disable_ipv6"])),("DNS",run(["resolvectl","status"])),("Google HTTPS",run(["bash","-c","curl -4 -sS -o /dev/null -w 'HTTP %{http_code} | IP %{remote_ip} | %{time_total}s' --max-time 10 https://www.google.com/"])),("Gemini HTTPS",run(["bash","-c","curl -4 -sS -o /dev/null -w 'HTTP %{http_code} | IP %{remote_ip} | %{time_total}s' --max-time 10 https://gemini.google.com/"])),("YouTube HTTPS",run(["bash","-c","curl -4 -sS -o /dev/null -w 'HTTP %{http_code} | IP %{remote_ip} | %{time_total}s' --max-time 10 https://www.youtube.com/"])),("Guardian log",run(["bash","-c","tail -40 /var/log/google-region-force-nl-guardian.log 2>/dev/null || echo no-log"])) ]
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path not in ("/","/index.html"):self.send_error(404);return
  rows="".join("<tr><th>"+html.escape(k)+"</th><td><pre>"+html.escape(v)+"</pre></td></tr>" for k,v in data())
  b=("<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><meta http-equiv=refresh content=60><title>Region NL</title><style>body{font:16px system-ui;background:#101722;color:#e6edf3;margin:18px}h1{color:#8bd5ff}table{width:100%;border-collapse:collapse}th,td{border:1px solid #34465a;padding:9px;text-align:left;vertical-align:top}th{width:180px;color:#a9d6ff}pre{white-space:pre-wrap;overflow-wrap:anywhere;margin:0}.muted{color:#9fb3c8}</style></head><body><h1>Google Region Force NL</h1><p class=muted>Read-only localhost dashboard · refresh 60s · "+html.escape(datetime.now().astimezone().isoformat())+"</p><table>"+rows+"</table><p class=muted>Reachability checks do not establish account-region eligibility. This dashboard is read-only and bound to loopback.</p></body></html>").encode()
  self.send_response(200);self.send_header("Content-Type","text/html; charset=utf-8");self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
 def log_message(self,*a):pass
if __name__=="__main__":HTTPServer((HOST,PORT),H).serve_forever()
