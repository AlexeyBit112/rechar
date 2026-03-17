# ⚡ RECHAR — Recon Harvester

> Bug Bounty Intelligence Pipeline for Kali Linux

```
  ██████╗ ███████╗ ██████╗██╗  ██╗ █████╗ ██████╗
  ██╔══██╗██╔════╝██╔════╝██║  ██║██╔══██╗██╔══██╗
  ██████╔╝█████╗  ██║     ███████║███████║██████╔╝
  ██╔══██╗██╔══╝  ██║     ██╔══██║██╔══██║██╔══██╗
  ██║  ██║███████╗╚██████╗██║  ██║██║  ██║██║  ██║
  ╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
```

Automated recon pipeline for bug bounty hunters. Runs subfinder → httpx → gau → ffuf → nuclei and outputs a structured report with all findings.

---

## 🚀 Install

```bash
sudo cp rechar.sh /usr/local/bin/rechar
sudo chmod +x /usr/local/bin/rechar
```

---

## 💻 Usage

```bash
# Basic run
rechar -d target.com

# Custom output dir and threads
rechar -d target.com -o ~/bounty -t 80

# Resume from a specific phase
rechar -d target.com -r 5 -p ~/bounty/recon_target.com_20260304_010101
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-d` | Target domain | required |
| `-t` | Threads | 50 |
| `-o` | Output directory | current dir |
| `-s` | Scope file (list of domains) | — |
| `-r` | Resume from phase (1–6) | 1 |
| `-p` | Path to existing recon dir (use with `-r`) | — |
| `-h` | Help | — |

---

## 🔧 Pipeline

| Phase | Tools | Output |
|-------|-------|--------|
| 1 — Subdomains | subfinder, assetfinder, crt.sh | `hosts/subdomains_all.txt` |
| 2 — Live Hosts | httpx | `hosts/live_urls.txt` |
| 3 — URLs & Params | gau, waybackurls, hakrawler | `urls/params.txt`, `urls/juicy_params.txt`, `urls/js_files.txt` |
| 4 — Port Scan | nmap | `ports/nmap_results.txt` |
| 5 — Fuzzing | ffuf + SecLists | `urls/ffuf_results.txt` |
| 6 — Vulns | nuclei | `vulns/nuclei_findings.txt` |

---

## 📁 Output Structure

```
recon_target.com_20260304_010101/
├── report/
│   ├── RECON_REPORT.txt     ← read this first
│   └── summary.html         ← HTML dashboard
├── hosts/
│   ├── subdomains_all.txt
│   ├── live_hosts.txt       ← with tech stack info
│   └── live_urls.txt
├── urls/
│   ├── all_urls.txt
│   ├── params.txt           ← XSS / SQLi / SSRF targets
│   ├── juicy_params.txt     ← high-value injection points
│   ├── js_files.txt         ← JS for secret hunting
│   ├── api_admin_paths.txt
│   └── ffuf_results.txt
├── vulns/
│   ├── nuclei_findings.txt
│   ├── nuclei_findings.json
│   └── exposures.txt
└── ports/
    ├── nmap_results.txt
    └── open_ports.txt
```

---

## 📦 Dependencies

Install Go tools:
```bash
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/tomnomnom/assetfinder@latest
go install github.com/hakluke/hakrawler@latest
go install github.com/ffuf/ffuf/v2@latest
```

System tools:
```bash
sudo apt install nmap seclists
```

---

## ⚡ Quick Commands

```bash
# Full summary
cat recon_target.com_*/report/RECON_REPORT.txt

# Live hosts
cat recon_target.com_*/hosts/live_urls.txt

# High-value injection targets
cat recon_target.com_*/urls/juicy_params.txt

# JS files for secret hunting
cat recon_target.com_*/urls/js_files.txt

# Nuclei findings
cat recon_target.com_*/vulns/nuclei_findings.txt

# HTML dashboard
xdg-open recon_target.com_*/report/summary.html
```

---

## 📝 Notes

- Hosts with latency > 2s are automatically skipped during ffuf fuzzing
- nuclei templates are auto-detected from `~/.local/nuclei-templates`
- Resume mode (`-r`) reuses existing output dir — skipped phases are read from saved files
- Rate: hardcoded at max 50 threads for passive tools, 25 for nuclei

---

## License

MIT
