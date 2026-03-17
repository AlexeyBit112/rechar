#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║                  RECHAR — Recon Harvester                       ║
# ║            Bug Bounty Intelligence Pipeline v1.0                ║
# ╚══════════════════════════════════════════════════════════════════╝
# Usage: ./rechar.sh -d target.com [-t threads] [-o output_dir] [-s scope_file]
# Install: chmod +x rechar.sh && sudo mv rechar.sh ~/tools/recon/

set -euo pipefail

# ─────────────────────────── COLORS ──────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;34m'
M='\033[0;35m'; C='\033[0;36m'; W='\033[0;37m'; BOLD='\033[1m'
DIM='\033[2m'; BLINK='\033[5m'; RESET='\033[0m'
RED_BG='\033[41m'; GRN_BG='\033[42m'; BLU_BG='\033[44m'

# ─────────────────────────── DEFAULTS ────────────────────────────
THREADS=50
OUTPUT_BASE="."
DOMAIN=""
SCOPE_FILE=""
RESUME_FROM=1
RESUME_DIR=""
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
START_TIME=$(date +%s)

# ─────────────────────────── BANNER ──────────────────────────────
banner() {
cat << 'EOF'
EOF
echo -e "${BOLD}${C}"
cat << 'BANNER'

  ██████╗ ███████╗ ██████╗██╗  ██╗ █████╗ ██████╗
  ██╔══██╗██╔════╝██╔════╝██║  ██║██╔══██╗██╔══██╗
  ██████╔╝█████╗  ██║     ███████║███████║██████╔╝
  ██╔══██╗██╔══╝  ██║     ██╔══██║██╔══██║██╔══██╗
  ██║  ██║███████╗╚██████╗██║  ██║██║  ██║██║  ██║
  ╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝
BANNER
echo -e "${DIM}${W}          Recon Harvester — Bug Bounty Intelligence Pipeline${RESET}"
echo -e "${DIM}${C}          ─────────────────────────────────────────────────${RESET}"
echo ""
}

# ─────────────────────────── HELPERS ─────────────────────────────
log()     { echo -e "${DIM}[$(date +%H:%M:%S)]${RESET} ${W}$1${RESET}"; }
info()    { echo -e "${DIM}[$(date +%H:%M:%S)]${RESET} ${C}[*]${RESET} $1"; }
success() { echo -e "${DIM}[$(date +%H:%M:%S)]${RESET} ${G}[✓]${RESET} $1"; }
warn()    { echo -e "${DIM}[$(date +%H:%M:%S)]${RESET} ${Y}[!]${RESET} $1"; }
error()   { echo -e "${DIM}[$(date +%H:%M:%S)]${RESET} ${R}[✗]${RESET} $1"; }
step()    { echo -e "\n${BOLD}${BLU_BG}  PHASE $1  ${RESET}${BOLD} $2${RESET}"; echo ""; }
divider() { echo -e "${DIM}${C}  ────────────────────────────────────────────────────${RESET}"; }

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        warn "Tool ${BOLD}$1${RESET} not found — skipping"
        return 1
    fi
    return 0
}

count_lines() {
    [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo "0"
}

progress_bar() {
    local msg="$1"
    local pid="$2"
    local delay=0.1
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${C}${spin[$i]}${RESET}  ${DIM}$msg${RESET}   "
        i=$(( (i+1) % 10 ))
        sleep "$delay"
    done
    printf "\r  ${G}✓${RESET}  ${DIM}$msg${RESET}  \n"
}

# ─────────────────────────── USAGE ───────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  ${C}./rechar.sh${RESET} ${Y}-d target.com${RESET} [options]"
    echo ""
    echo -e "${BOLD}Options:${RESET}"
    echo -e "  ${Y}-d${RESET}  Target domain                ${DIM}(required)${RESET}"
    echo -e "  ${Y}-t${RESET}  Threads                      ${DIM}(default: 50)${RESET}"
    echo -e "  ${Y}-o${RESET}  Output directory             ${DIM}(default: current dir)${RESET}"
    echo -e "  ${Y}-s${RESET}  Scope file (domains list)    ${DIM}(optional)${RESET}"
    echo -e "  ${Y}-r${RESET}  Resume from phase (1-6)      ${DIM}(default: 1)${RESET}"
    echo -e "  ${Y}-p${RESET}  Path to existing recon dir   ${DIM}(required with -r)${RESET}"
    echo -e "  ${Y}-h${RESET}  Show this help"
    echo ""
    exit 0
}

# ─────────────────────────── ARGS ────────────────────────────────
while getopts "d:t:o:s:r:p:h" opt; do
    case $opt in
        d) DOMAIN="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        o) OUTPUT_BASE="$OPTARG" ;;
        s) SCOPE_FILE="$OPTARG" ;;
        r) RESUME_FROM="$OPTARG" ;;
        p) RESUME_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ─────────────────────────── RESUME LOGIC ───────────────────────
# Resume mode: -r PHASE -p /path/to/existing/recon_dir
if [[ -n "$RESUME_DIR" ]]; then
    # Resume mode — используем существующую папку
    [[ ! -d "$RESUME_DIR" ]] && { banner; error "Resume dir not found: ${Y}${RESUME_DIR}${RESET}"; exit 1; }
    OUT_DIR="${RESUME_DIR}"
    # Вытащить домен из имени папки если -d не задан
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN=$(basename "$OUT_DIR" | sed 's/recon_//;s/_[0-9]*$//')
    fi
    echo -e "  ${BOLD}${Y}[RESUME]${RESET} Continuing from phase ${BOLD}${RESUME_FROM}${RESET}"
    echo -e "  ${BOLD}${Y}[RESUME]${RESET} Using dir: ${C}${OUT_DIR}${RESET}"
    echo ""
else
    # Обычный запуск — нужен домен
    [[ -z "$DOMAIN" ]] && { banner; error "Domain required. Use ${Y}-d target.com${RESET}"; echo ""; usage; }
    OUT_DIR="${OUTPUT_BASE}/recon_${DOMAIN}_${TIMESTAMP}"
fi

# ─────────────────────────── DIRS ────────────────────────────────
REPORT_DIR="${OUT_DIR}/report"
HOSTS_DIR="${OUT_DIR}/hosts"
URLS_DIR="${OUT_DIR}/urls"
VULNS_DIR="${OUT_DIR}/vulns"
PORTS_DIR="${OUT_DIR}/ports"
SCREENSHOTS_DIR="${OUT_DIR}/screenshots"

mkdir -p "$REPORT_DIR" "$HOSTS_DIR" "$URLS_DIR" "$VULNS_DIR" "$PORTS_DIR" "$SCREENSHOTS_DIR"

REPORT="${REPORT_DIR}/RECON_REPORT.txt"
SUMMARY_HTML="${REPORT_DIR}/summary.html"

# Helper: пропустить фазу если resume
should_run_phase() {
    local phase_num="$1"
    [[ "$phase_num" -ge "$RESUME_FROM" ]]
}

# ─────────────────────────── INIT ────────────────────────────────
banner
divider
echo -e "  ${BOLD}Target:${RESET}    ${Y}${DOMAIN}${RESET}"
echo -e "  ${BOLD}Threads:${RESET}   ${W}${THREADS}${RESET}"
echo -e "  ${BOLD}Output:${RESET}    ${C}${OUT_DIR}${RESET}"
if [[ "$RESUME_FROM" -gt 1 ]]; then
echo -e "  ${BOLD}Resume:${RESET}    ${Y}Starting from phase ${RESUME_FROM}${RESET}"
fi
echo -e "  ${BOLD}Started:${RESET}   ${DIM}$(date)${RESET}"
divider
echo ""

# Write report header
{
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║               RECHAR — Recon Harvester Report                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Target   : $DOMAIN"
echo "Date     : $(date)"
echo "Output   : $OUT_DIR"
echo ""
echo "════════════════════════════════════════════════════════════════════"
} > "$REPORT"

# ════════════════════════════════════════════════════════════════════
# PHASE 1: SUBDOMAIN ENUMERATION
# ════════════════════════════════════════════════════════════════════
if should_run_phase 1; then
step "1/6" "SUBDOMAIN ENUMERATION"

SUBS_RAW="${HOSTS_DIR}/subdomains_raw.txt"
SUBS_ALL="${HOSTS_DIR}/subdomains_all.txt"

if check_tool subfinder; then
    info "Running subfinder..."
    subfinder -d "$DOMAIN" -silent -t "$THREADS" -o "${HOSTS_DIR}/subfinder.txt" 2>/dev/null &
    progress_bar "subfinder passive enumeration" $!
fi

if check_tool assetfinder; then
    info "Running assetfinder..."
    assetfinder --subs-only "$DOMAIN" > "${HOSTS_DIR}/assetfinder.txt" 2>/dev/null &
    progress_bar "assetfinder enumeration" $!
fi

# Certificate transparency
info "Querying crt.sh..."
curl -s "https://crt.sh/?q=%.${DOMAIN}&output=json" 2>/dev/null \
    | grep -o '"name_value":"[^"]*"' \
    | sed 's/"name_value":"//;s/"//' \
    | sed 's/\*\.//g' \
    | sort -u > "${HOSTS_DIR}/crtsh.txt" 2>/dev/null || true

# Merge all subdomains
cat "${HOSTS_DIR}"/*.txt 2>/dev/null | sort -u | grep -E "\.${DOMAIN}$|^${DOMAIN}$" | grep -v '^$' > "$SUBS_ALL" 2>/dev/null || true
echo "$DOMAIN" >> "$SUBS_ALL"
sort -u "$SUBS_ALL" -o "$SUBS_ALL"

SUBS_COUNT=$(count_lines "$SUBS_ALL")
success "Found ${BOLD}${Y}${SUBS_COUNT}${RESET} unique subdomains"

fi # end phase 1

# ════════════════════════════════════════════════════════════════════
# PHASE 2: LIVE HOST DETECTION
# ════════════════════════════════════════════════════════════════════
# In resume mode, reload existing data from previous phases
SUBS_ALL="${HOSTS_DIR}/subdomains_all.txt"
LIVE_HOSTS="${HOSTS_DIR}/live_hosts.txt"
LIVE_URLS="${HOSTS_DIR}/live_urls.txt"

if should_run_phase 2; then
step "2/6" "LIVE HOST DETECTION"

LIVE_HOSTS="${HOSTS_DIR}/live_hosts.txt"
LIVE_URLS="${HOSTS_DIR}/live_urls.txt"

HTTPX_BIN="/home/kali/go/bin/httpx"
[[ -f "$HTTPX_BIN" ]] || HTTPX_BIN="$(command -v httpx 2>/dev/null || true)"

if [[ -n "$HTTPX_BIN" && -f "$HTTPX_BIN" ]]; then
    info "Probing with httpx..."
    "$HTTPX_BIN" -l "$SUBS_ALL" \
        -silent \
        -threads "$THREADS" \
        -follow-redirects \
        -status-code \
        -title \
        -tech-detect \
        -web-server \
        -content-length \
        -o "$LIVE_HOSTS" 2>/dev/null &
    progress_bar "httpx probing live hosts" $!

    # Extract clean URLs
    awk '{print $1}' "$LIVE_HOSTS" 2>/dev/null | sort -u > "$LIVE_URLS" || true
elif check_tool httprobe; then
    cat "$SUBS_ALL" | httprobe -c "$THREADS" > "$LIVE_URLS" 2>/dev/null &
    progress_bar "httprobe probing" $!
    cp "$LIVE_URLS" "$LIVE_HOSTS"
else
    # Fallback: basic curl check
    warn "No httpx/httprobe found, using curl fallback..."
    while IFS= read -r sub; do
        if curl -sk --max-time 5 "https://$sub" -o /dev/null 2>/dev/null; then
            echo "https://$sub" >> "$LIVE_URLS"
        elif curl -sk --max-time 5 "http://$sub" -o /dev/null 2>/dev/null; then
            echo "http://$sub" >> "$LIVE_URLS"
        fi
    done < "$SUBS_ALL"
fi

LIVE_COUNT=$(count_lines "$LIVE_URLS")
success "Found ${BOLD}${Y}${LIVE_COUNT}${RESET} live hosts"

fi # end phase 2

# ════════════════════════════════════════════════════════════════════
# PHASE 3: URL & PARAM DISCOVERY
# ════════════════════════════════════════════════════════════════════
if should_run_phase 3; then
step "3/6" "URL & PARAMETER DISCOVERY"

ALL_URLS="${URLS_DIR}/all_urls.txt"
PARAMS_FILE="${URLS_DIR}/params.txt"
JS_FILES="${URLS_DIR}/js_files.txt"
API_PATHS="${URLS_DIR}/api_admin_paths.txt"
URL_SOURCES=()

# gau — запускаем синхронно чтобы дождаться результата
GAU_BIN=""
for p in "$HOME/go/bin/gau" "/home/kali/go/bin/gau" "$(command -v gau 2>/dev/null)"; do
    [[ -f "$p" ]] && { GAU_BIN="$p"; break; }
done

if [[ -n "$GAU_BIN" ]]; then
    info "Fetching URLs via gau (Wayback + Common Crawl)..."
    GAU_FILE="${URLS_DIR}/gau.txt"
    # Запуск с timeout 180s, синхронно — ждём результат
    timeout 180 "$GAU_BIN" --threads "$THREADS" --subs "$DOMAIN" \
        --providers wayback,commoncrawl,otx \
        --blacklist ttf,woff,woff2,eot,svg,png,jpg,jpeg,gif,ico,css \
        > "$GAU_FILE" 2>/dev/null || true
    GAU_COUNT=$(count_lines "$GAU_FILE")
    success "gau collected ${BOLD}${Y}${GAU_COUNT}${RESET} URLs"
    [[ "$GAU_COUNT" -gt 0 ]] && URL_SOURCES+=("$GAU_FILE")
else
    warn "gau not found"
fi

# waybackurls — как дополнительный источник если gau дал мало
WB_BIN=""
for p in "$HOME/go/bin/waybackurls" "/home/kali/go/bin/waybackurls" "$(command -v waybackurls 2>/dev/null)"; do
    [[ -f "$p" ]] && { WB_BIN="$p"; break; }
done

WB_COUNT=0
if [[ -n "$WB_BIN" ]]; then
    info "Fetching URLs via waybackurls..."
    WB_FILE="${URLS_DIR}/wayback.txt"
    echo "$DOMAIN" | timeout 120 "$WB_BIN" > "$WB_FILE" 2>/dev/null || true
    WB_COUNT=$(count_lines "$WB_FILE")
    success "waybackurls collected ${BOLD}${Y}${WB_COUNT}${RESET} URLs"
    [[ "$WB_COUNT" -gt 0 ]] && URL_SOURCES+=("$WB_FILE")
fi

# hakrawler
HAKRAWLER_BIN=""
for p in "$HOME/go/bin/hakrawler" "/home/kali/go/bin/hakrawler" "$(command -v hakrawler 2>/dev/null)"; do
    [[ -f "$p" ]] && { HAKRAWLER_BIN="$p"; break; }
done

if [[ -n "$HAKRAWLER_BIN" ]] && [[ -s "$LIVE_URLS" ]]; then
    info "Running hakrawler..."
    HAK_FILE="${URLS_DIR}/hakrawler.txt"
    cat "$LIVE_URLS" | timeout 120 "$HAKRAWLER_BIN" -t "$THREADS" -subs 2>/dev/null > "$HAK_FILE" || true
    HAK_COUNT=$(count_lines "$HAK_FILE")
    success "hakrawler collected ${BOLD}${Y}${HAK_COUNT}${RESET} URLs"
    [[ "$HAK_COUNT" -gt 0 ]] && URL_SOURCES+=("$HAK_FILE")
else
    warn "hakrawler not found — install: go install github.com/hakluke/hakrawler@latest"
fi

# Merge all URL sources
info "Merging URL sources..."
if [[ ${#URL_SOURCES[@]} -gt 0 ]]; then
    cat "${URL_SOURCES[@]}" 2>/dev/null | \
        grep -aE "^https?://" | \
        sort -u | \
        grep -v '^$' > "$ALL_URLS" || true
else
    touch "$ALL_URLS"
fi

TOTAL_URLS=$(count_lines "$ALL_URLS")
success "Collected ${BOLD}${Y}${TOTAL_URLS}${RESET} unique URLs"

# Extract JS files
info "Extracting JS files..."
grep -iE "\.js(\?|$)" "$ALL_URLS" 2>/dev/null | sort -u > "$JS_FILES" || true
JS_COUNT=$(count_lines "$JS_FILES")
success "Found ${BOLD}${Y}${JS_COUNT}${RESET} JS files"

# Extract URLs with parameters
info "Extracting parameterized URLs..."
grep '?' "$ALL_URLS" 2>/dev/null | sort -u > "$PARAMS_FILE" || true
PARAMS_COUNT=$(count_lines "$PARAMS_FILE")
success "Found ${BOLD}${Y}${PARAMS_COUNT}${RESET} URLs with parameters"

# Juicy params (XSS, SQLi, SSRF, RCE)
JUICY_PARAMS_FILE="${URLS_DIR}/juicy_params.txt"
JUICY_KEYWORDS="url=|redirect=|uri=|path=|dest=|target=|src=|source=|ref=|href=|link=|page=|file=|document=|folder=|root=|base=|template=|php_path=|resource=|loadfile=|dir=|show=|site=|cat=|include=|search=|q=|query=|keyword=|id=|user=|name=|cmd=|exec=|command=|run=|callback=|host=|proxy=|to=|from=|debug=|admin=|token=|key=|secret=|password=|pass=|username=|email=|next=|return=|returnto=|returnurl=|checkout_url=|continue=|data=|xml=|payload=|input=|output=|format=|type=|action="
grep -iE "$JUICY_KEYWORDS" "$PARAMS_FILE" 2>/dev/null | sort -u > "$JUICY_PARAMS_FILE" || true
JUICY_COUNT=$(count_lines "$JUICY_PARAMS_FILE")
success "Found ${BOLD}${Y}${JUICY_COUNT}${RESET} juicy parameter URLs"

# API / Admin paths
info "Finding API & admin paths..."
grep -iE "(api|admin|v1|v2|v3|graphql|swagger|actuator|debug|test|stage|dev|dashboard|panel|manage|config|setup|install|backup|login|auth|oauth|token|signup|register)" "$ALL_URLS" 2>/dev/null | sort -u > "$API_PATHS" || true
API_COUNT=$(count_lines "$API_PATHS")
success "Found ${BOLD}${Y}${API_COUNT}${RESET} API/Admin paths"

fi # end phase 3

# ════════════════════════════════════════════════════════════════════
# PHASE 4: PORT SCANNING
# ════════════════════════════════════════════════════════════════════
if should_run_phase 4; then
step "4/6" "PORT SCANNING"

NMAP_OUT="${PORTS_DIR}/nmap_results.txt"
OPEN_PORTS="${PORTS_DIR}/open_ports.txt"

if check_tool nmap; then
    info "Running nmap on live hosts (top ports, fast)..."
    # Extract hostnames for nmap
    sed 's|https\?://||g' "$LIVE_URLS" | cut -d'/' -f1 | cut -d':' -f1 | sort -u > "${PORTS_DIR}/hosts_for_scan.txt"
    HOST_COUNT=$(count_lines "${PORTS_DIR}/hosts_for_scan.txt")
    
    if [[ "$HOST_COUNT" -gt 50 ]]; then
        warn "Too many hosts ($HOST_COUNT), scanning sample of 50..."
        head -50 "${PORTS_DIR}/hosts_for_scan.txt" > "${PORTS_DIR}/hosts_sample.txt"
        SCAN_FILE="${PORTS_DIR}/hosts_sample.txt"
    else
        SCAN_FILE="${PORTS_DIR}/hosts_for_scan.txt"
    fi
    
    nmap -iL "$SCAN_FILE" \
        --top-ports 1000 \
        -T4 \
        -oN "$NMAP_OUT" \
        --open \
        -Pn \
        2>/dev/null &
    progress_bar "nmap port scanning" $!
    
    # Extract open ports summary
    grep -E "^[0-9]+\/tcp.*open" "$NMAP_OUT" 2>/dev/null | sort | uniq -c | sort -rn > "$OPEN_PORTS" || true
    PORTS_COUNT=$(count_lines "$OPEN_PORTS")
    success "Found ${BOLD}${Y}${PORTS_COUNT}${RESET} unique open port/service combos"
else
    warn "nmap not found — skipping port scan"
    PORTS_COUNT=0
fi

fi # end phase 4

# ════════════════════════════════════════════════════════════════════
# PHASE 5: FUZZING
# ════════════════════════════════════════════════════════════════════
if should_run_phase 5; then
step "5/6" "DIRECTORY FUZZING"

FFUF_OUT="${URLS_DIR}/ffuf_results.txt"
FUZZ_COUNT=0

if check_tool ffuf; then
    # Pick a wordlist
    WORDLIST=""
    for wl in \
        "/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt" \
        "/usr/share/wordlists/dirb/common.txt" \
        "/usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt"; do
        [[ -f "$wl" ]] && { WORDLIST="$wl"; break; }
    done

    if [[ -n "$WORDLIST" ]]; then
        info "Fuzzing top live hosts with ffuf..."
        # Fuzz top 10 hosts
        TOP_HOSTS=$(head -10 "$LIVE_URLS" 2>/dev/null)
        > "$FFUF_OUT"
        
        while IFS= read -r host_url; do
            [[ -z "$host_url" ]] && continue
            LATENCY=$(curl -o /dev/null -sk --max-time 5 -w "%{time_total}\n" "$host_url" 2>/dev/null || echo "99")
            LATENCY_INT=$(echo "$LATENCY" | cut -d'.' -f1)
            if [[ "$LATENCY_INT" -ge 2 ]]; then
                warn "Skipping $host_url — latency ${LATENCY}s"
                continue
            fi
            echo "--- Fuzzing: $host_url ---" >> "$FFUF_OUT"
            ffuf -u "${host_url}/FUZZ" \
                -w "$WORDLIST" \
                -t "$THREADS" \
                -mc 200,201,301,302,401,403 \
                -o /dev/null \
                -of csv \
                -s 2>/dev/null \
                | grep -v "^#" >> "$FFUF_OUT" 2>/dev/null || true
        done <<< "$TOP_HOSTS" 
        
        FUZZ_COUNT=$(grep -c "200\|301\|302" "$FFUF_OUT" 2>/dev/null || echo 0)
        success "Found ${BOLD}${Y}${FUZZ_COUNT}${RESET} interesting paths via fuzzing"
    else
        warn "No wordlist found — install SecLists or dirb"
    fi
else
    warn "ffuf not found — skipping fuzzing"
fi

fi # end phase 5

# ════════════════════════════════════════════════════════════════════
# PHASE 6: VULNERABILITY SCANNING
# ════════════════════════════════════════════════════════════════════
if should_run_phase 6; then
step "6/6" "VULNERABILITY SCANNING"

NUCLEI_OUT="${VULNS_DIR}/nuclei_findings.txt"
NUCLEI_JSON="${VULNS_DIR}/nuclei_findings.json"
EXPOSURES_OUT="${VULNS_DIR}/exposures.txt"
VULN_COUNT=0
EXPOSURE_COUNT=0

if check_tool nuclei; then
    info "Updating nuclei templates..."
    nuclei -update-templates -silent 2>/dev/null || true
    
    info "Running nuclei on live hosts..."
    NUCLEI_TEMPLATES=""
    for td in "$HOME/.local/nuclei-templates" "$HOME/nuclei-templates" "/root/nuclei-templates"; do
        [[ -d "$td" ]] && { NUCLEI_TEMPLATES="$td"; break; }
    done

    nuclei -l "$LIVE_URLS" \
        -t "${NUCLEI_TEMPLATES}/http/cves/" \
        -t "${NUCLEI_TEMPLATES}/http/exposures/" \
        -t "${NUCLEI_TEMPLATES}/http/misconfiguration/" \
        -t "${NUCLEI_TEMPLATES}/http/takeovers/" \
        -t "${NUCLEI_TEMPLATES}/http/vulnerabilities/" \
        -severity low,medium,high,critical \
        -c 25 \
        -o "$NUCLEI_OUT" \
        -json-export "$NUCLEI_JSON" \
        2>/dev/null
    
    VULN_COUNT=$(grep -cE "\[critical\]|\[high\]|\[medium\]|\[low\]" "$NUCLEI_OUT" 2>/dev/null || echo 0)
    EXPOSURE_COUNT=$(grep -ci "exposure\|misconfiguration\|takeover" "$NUCLEI_OUT" 2>/dev/null || echo 0)
    
    # Separate exposures
    grep -iE "exposure|misconfiguration|takeover" "$NUCLEI_OUT" > "$EXPOSURES_OUT" 2>/dev/null || true
    
    success "Found ${BOLD}${R}${VULN_COUNT}${RESET} vulnerabilities, ${BOLD}${Y}${EXPOSURE_COUNT}${RESET} exposures"
else
    warn "nuclei not found — skipping vulnerability scan"
fi

fi # end phase 6

# ════════════════════════════════════════════════════════════════════
# GENERATE REPORT
# ════════════════════════════════════════════════════════════════════

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MIN=$((ELAPSED / 60))
ELAPSED_SEC=$((ELAPSED % 60))

# Ensure all path vars exist even if phases were skipped (resume mode)
SUBS_ALL="${SUBS_ALL:-${HOSTS_DIR}/subdomains_all.txt}"
LIVE_URLS="${LIVE_URLS:-${HOSTS_DIR}/live_urls.txt}"
LIVE_HOSTS="${LIVE_HOSTS:-${HOSTS_DIR}/live_hosts.txt}"
ALL_URLS="${ALL_URLS:-${URLS_DIR}/all_urls.txt}"
PARAMS_FILE="${PARAMS_FILE:-${URLS_DIR}/params.txt}"
JUICY_PARAMS_FILE="${JUICY_PARAMS_FILE:-${URLS_DIR}/juicy_params.txt}"
JS_FILES="${JS_FILES:-${URLS_DIR}/js_files.txt}"
API_PATHS="${API_PATHS:-${URLS_DIR}/api_admin_paths.txt}"
NUCLEI_OUT="${NUCLEI_OUT:-${VULNS_DIR}/nuclei_findings.txt}"
FFUF_OUT="${FFUF_OUT:-${URLS_DIR}/ffuf_results.txt}"

# Refresh counts
SUBS_COUNT=$(count_lines "$SUBS_ALL")
LIVE_COUNT=$(count_lines "$LIVE_URLS")
TOTAL_URLS=$(count_lines "$ALL_URLS")
PARAMS_COUNT=$(count_lines "$PARAMS_FILE")
JUICY_COUNT=$(count_lines "$JUICY_PARAMS_FILE")
JS_COUNT=$(count_lines "$JS_FILES")
API_COUNT=$(count_lines "$API_PATHS")
VULN_COUNT=${VULN_COUNT:-$(grep -cE "\[critical\]|\[high\]|\[medium\]|\[low\]" "$NUCLEI_OUT" 2>/dev/null || echo 0)}
EXPOSURE_COUNT=${EXPOSURE_COUNT:-$(grep -ci "exposure\|misconfiguration\|takeover" "$NUCLEI_OUT" 2>/dev/null || echo 0)}
PORTS_COUNT=${PORTS_COUNT:-0}
FUZZ_COUNT=${FUZZ_COUNT:-0}

# Write text report
{
cat << REOF
════════════════════════════════════════════════════════════════════
  RECON SUMMARY — ${DOMAIN}
════════════════════════════════════════════════════════════════════

  Completed : $(date)
  Duration  : ${ELAPSED_MIN}m ${ELAPSED_SEC}s

╔═══════════════════════════════════════════════════════════════╗
║                    FINDINGS OVERVIEW                          ║
╠═══════════════════════╦═══════════════════════════════════════╣
║  Metric               ║  Count                                ║
╠═══════════════════════╬═══════════════════════════════════════╣
║  🔭 Subdomains        ║  $SUBS_COUNT
║  🌐 Live Hosts        ║  $LIVE_COUNT
║  🗂️  Total URLs       ║  $TOTAL_URLS
║  🎯 With Params       ║  $PARAMS_COUNT
║  💎 Juicy Params      ║  $JUICY_COUNT
║  📜 JS Files          ║  $JS_COUNT
║  🔑 API/Admin Paths   ║  $API_COUNT
║  🐛 Vulnerabilities   ║  $VULN_COUNT
║  ⚡ Exposures         ║  $EXPOSURE_COUNT
╚═══════════════════════╩═══════════════════════════════════════╝

════════════════════════════════════════════════════════════════════
  FILES
════════════════════════════════════════════════════════════════════

  hosts/subdomains_all.txt  →  All discovered subdomains
  hosts/live_urls.txt       →  Live hosts for manual testing
  hosts/live_hosts.txt      →  Live hosts with tech stack info
  urls/all_urls.txt         →  All discovered URLs
  urls/params.txt           →  URLs with parameters
  urls/juicy_params.txt     →  High-value parameter URLs (XSS/SQLi/SSRF)
  urls/js_files.txt         →  JS files (secrets & endpoints)
  urls/api_admin_paths.txt  →  API & admin paths
  vulns/nuclei_findings.txt →  Vulnerability scan results
  vulns/exposures.txt       →  Misconfigs & exposures
  ports/nmap_results.txt    →  Port scan results

════════════════════════════════════════════════════════════════════
  TOP LIVE HOSTS
════════════════════════════════════════════════════════════════════

REOF

head -20 "$LIVE_HOSTS" 2>/dev/null || head -20 "$LIVE_URLS" 2>/dev/null || echo "  (none)"

cat << 'REOF2'

════════════════════════════════════════════════════════════════════
  VULNERABILITIES (nuclei)
════════════════════════════════════════════════════════════════════

REOF2

if [[ -f "$NUCLEI_OUT" ]] && [[ -s "$NUCLEI_OUT" ]]; then
    cat "$NUCLEI_OUT"
else
    echo "  No findings or nuclei not run"
fi

cat << 'REOF3'

════════════════════════════════════════════════════════════════════
  JUICY PARAMS (top 50)
════════════════════════════════════════════════════════════════════

REOF3
head -50 "$JUICY_PARAMS_FILE" 2>/dev/null || echo "  (none)"

cat << 'REOF4'

════════════════════════════════════════════════════════════════════
  API / ADMIN PATHS (top 50)
════════════════════════════════════════════════════════════════════

REOF4
head -50 "$API_PATHS" 2>/dev/null || echo "  (none)"

} >> "$REPORT"

# ════════════════════════════════════════════════════════════════════
# GENERATE HTML SUMMARY
# ════════════════════════════════════════════════════════════════════
cat > "$SUMMARY_HTML" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RECHAR — ${DOMAIN}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;600;700&family=Space+Mono:wght@400;700&display=swap');
  :root {
    --bg: #0a0d14; --bg2: #0e1320; --bg3: #141926;
    --border: #1e2d4a; --accent: #00d4ff; --accent2: #ff3366;
    --green: #00ff9d; --yellow: #ffd93d; --orange: #ff8c42;
    --text: #c8d8e8; --dim: #4a5a7a;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: var(--bg); color: var(--text); font-family: 'JetBrains Mono', monospace; min-height: 100vh; }
  .header { background: linear-gradient(135deg, var(--bg2), var(--bg3)); border-bottom: 1px solid var(--border); padding: 2rem 3rem; }
  .header h1 { font-family: 'Space Mono', monospace; font-size: 2rem; color: var(--accent); letter-spacing: 4px; text-transform: uppercase; }
  .header .target { color: var(--yellow); font-size: 1.1rem; margin-top: 0.5rem; }
  .header .meta { color: var(--dim); font-size: 0.75rem; margin-top: 0.3rem; }
  .container { padding: 2rem 3rem; max-width: 1400px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin: 2rem 0; }
  .stat-card { background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 1.5rem; transition: border-color 0.2s; position: relative; overflow: hidden; }
  .stat-card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px; background: linear-gradient(90deg, transparent, var(--accent), transparent); opacity: 0.5; }
  .stat-card:hover { border-color: var(--accent); }
  .stat-card .icon { font-size: 1.5rem; margin-bottom: 0.5rem; }
  .stat-card .value { font-size: 2.5rem; font-weight: 700; line-height: 1; }
  .stat-card .label { color: var(--dim); font-size: 0.7rem; text-transform: uppercase; letter-spacing: 2px; margin-top: 0.3rem; }
  .stat-card.danger .value { color: var(--accent2); }
  .stat-card.warn .value { color: var(--orange); }
  .stat-card.ok .value { color: var(--green); }
  .stat-card.info .value { color: var(--accent); }
  .stat-card.dim .value { color: var(--yellow); }
  .section { margin: 2rem 0; }
  .section-title { font-family: 'Space Mono', monospace; color: var(--accent); font-size: 0.8rem; letter-spacing: 3px; text-transform: uppercase; margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--border); }
  .file-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 0.75rem; }
  .file-item { background: var(--bg2); border: 1px solid var(--border); border-radius: 6px; padding: 1rem; display: flex; align-items: center; gap: 1rem; }
  .file-item .file-icon { color: var(--accent); font-size: 1.2rem; flex-shrink: 0; }
  .file-item .file-name { color: var(--green); font-size: 0.8rem; word-break: break-all; }
  .file-item .file-desc { color: var(--dim); font-size: 0.7rem; }
  .vuln-count { display: inline-block; padding: 0.2rem 0.6rem; border-radius: 4px; font-size: 0.75rem; font-weight: 700; }
  .critical { background: rgba(255,51,102,0.2); color: var(--accent2); border: 1px solid rgba(255,51,102,0.4); }
  .high { background: rgba(255,140,66,0.2); color: var(--orange); border: 1px solid rgba(255,140,66,0.4); }
  .medium { background: rgba(255,217,61,0.2); color: var(--yellow); border: 1px solid rgba(255,217,61,0.4); }
  footer { text-align: center; padding: 2rem; color: var(--dim); font-size: 0.7rem; border-top: 1px solid var(--border); margin-top: 3rem; }
</style>
</head>
<body>
<div class="header">
  <h1>⚡ RECHAR</h1>
  <div class="target">🎯 Target: ${DOMAIN}</div>
  <div class="meta">Generated: $(date) | Duration: ${ELAPSED_MIN}m ${ELAPSED_SEC}s</div>
</div>
<div class="container">
  <div class="grid">
    <div class="stat-card info"><div class="icon">🔭</div><div class="value">${SUBS_COUNT}</div><div class="label">Subdomains</div></div>
    <div class="stat-card ok"><div class="icon">🌐</div><div class="value">${LIVE_COUNT}</div><div class="label">Live Hosts</div></div>
    <div class="stat-card dim"><div class="icon">🗂️</div><div class="value">${TOTAL_URLS}</div><div class="label">Total URLs</div></div>
    <div class="stat-card warn"><div class="icon">🎯</div><div class="value">${PARAMS_COUNT}</div><div class="label">With Params</div></div>
    <div class="stat-card warn"><div class="icon">💎</div><div class="value">${JUICY_COUNT}</div><div class="label">Juicy Params</div></div>
    <div class="stat-card info"><div class="icon">📜</div><div class="value">${JS_COUNT}</div><div class="label">JS Files</div></div>
    <div class="stat-card dim"><div class="icon">🔑</div><div class="value">${API_COUNT}</div><div class="label">API/Admin Paths</div></div>
    <div class="stat-card danger"><div class="icon">🐛</div><div class="value">${VULN_COUNT}</div><div class="label">Vulnerabilities</div></div>
    <div class="stat-card warn"><div class="icon">⚡</div><div class="value">${EXPOSURE_COUNT}</div><div class="label">Exposures</div></div>
  </div>

  <div class="section">
    <div class="section-title">📁 Output Files</div>
    <div class="file-grid">
      <div class="file-item"><div class="file-icon">📋</div><div><div class="file-name">report/RECON_REPORT.txt</div><div class="file-desc">Full recon report — read this first</div></div></div>
      <div class="file-item"><div class="file-icon">🌐</div><div><div class="file-name">hosts/live_urls.txt</div><div class="file-desc">Live servers for manual testing</div></div></div>
      <div class="file-item"><div class="file-icon">🎯</div><div><div class="file-name">urls/params.txt</div><div class="file-desc">XSS, SQLi, SSRF targets</div></div></div>
      <div class="file-item"><div class="file-icon">💎</div><div><div class="file-name">urls/juicy_params.txt</div><div class="file-desc">High-value injection points</div></div></div>
      <div class="file-item"><div class="file-icon">📜</div><div><div class="file-name">urls/js_files.txt</div><div class="file-desc">JS for secrets & endpoints</div></div></div>
      <div class="file-item"><div class="file-icon">🔑</div><div><div class="file-name">urls/api_admin_paths.txt</div><div class="file-desc">API & admin paths</div></div></div>
      <div class="file-item"><div class="file-icon">🐛</div><div><div class="file-name">vulns/nuclei_findings.txt</div><div class="file-desc">Ready-to-report findings</div></div></div>
      <div class="file-item"><div class="file-icon">⚡</div><div><div class="file-name">vulns/exposures.txt</div><div class="file-desc">Misconfigs & exposures</div></div></div>
      <div class="file-item"><div class="file-icon">🔍</div><div><div class="file-name">ports/nmap_results.txt</div><div class="file-desc">Open ports & services</div></div></div>
    </div>
  </div>
</div>
<footer>RECHAR v1.0 — Bug Bounty Recon Pipeline | ${DOMAIN} | $(date +%Y)</footer>
</body>
</html>
HTMLEOF

# ════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════════
echo ""
divider
echo -e ""
echo -e "  ${BOLD}${C}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "  ${BOLD}${C}║${RESET}  ${BOLD}RECON COMPLETE — ${Y}${DOMAIN}${RESET}              ${BOLD}${C}║${RESET}"
echo -e "  ${BOLD}${C}╠══════════════════════════════════════════════════╣${RESET}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${C}%s${RESET}\n" "🔭  Subdomains"       "${SUBS_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${G}%s${RESET}\n" "🌐  Live Hosts"       "${LIVE_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${Y}%s${RESET}\n" "🗂️   Total URLs"       "${TOTAL_URLS}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${Y}%s${RESET}\n" "🎯  With Parameters"  "${PARAMS_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${M}%s${RESET}\n" "💎  Juicy Params"     "${JUICY_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${C}%s${RESET}\n" "📜  JS Files"         "${JS_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${Y}%s${RESET}\n" "🔑  API/Admin Paths"  "${API_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${R}%s${RESET}\n" "🐛  Vulnerabilities"  "${VULN_COUNT}"
printf "  ${C}║${RESET}  %-30s ${BOLD}${Y}%s${RESET}\n" "⚡  Exposures"        "${EXPOSURE_COUNT}"
echo -e "  ${BOLD}${C}╠══════════════════════════════════════════════════╣${RESET}"
echo -e "  ${BOLD}${C}║${RESET}  ⏱️  Duration: ${W}${ELAPSED_MIN}m ${ELAPSED_SEC}s${RESET}                           ${BOLD}${C}║${RESET}"
echo -e "  ${BOLD}${C}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
divider
echo ""
echo -e "  ${BOLD}Output:${RESET} ${Y}${OUT_DIR}/${RESET}"
echo ""
echo -e "  ${DIM}Quick Access:${RESET}"
echo -e "  ${C}cat${RESET} ${W}${REPORT}${RESET}"
echo -e "  ${C}cat${RESET} ${W}${LIVE_URLS}${RESET}"
echo -e "  ${C}cat${RESET} ${W}${JUICY_PARAMS_FILE}${RESET}"
if [[ -s "$NUCLEI_OUT" ]]; then
echo -e "  ${C}cat${RESET} ${W}${NUCLEI_OUT}${RESET}"
fi
echo -e "  ${C}xdg-open${RESET} ${W}${SUMMARY_HTML}${RESET}  ${DIM}← HTML dashboard${RESET}"
echo ""
divider
echo ""

exit 0
                
