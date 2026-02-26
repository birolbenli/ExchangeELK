#!/bin/bash

# ================================================================
# Exchange ELK Stack - Ana Deployment Scripti
# Ubuntu 22.04 LTS | 600 mailbox | 90 gun retention
# Sistem diski: 100 GB (OS+Docker metadata)
# Data diski  : 2 TB (tum ES/Logstash/log verisi)
# ================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BLUE}>>> $*${NC}"; }

# ---- Parametreler -------------------------------------------
GITHUB_REPO="${1:-https://github.com/yourorg/ExchangeELK.git}"
DATA_DISK="${2:-/dev/sdb}"   # 2. disk (otomatik algilama yapilir)
INSTALL_DIR="/opt/exchange-elk"

# ---- Root kontrolu ------------------------------------------
[[ "$EUID" -ne 0 ]] && error "sudo ile calistirin: sudo $0"

# ---- 1. SISTEM GEREKSINIMLERI KONTROL -----------------------
step "Sistem kontrolleri yapiliyor..."

RAM_GB=$(free -g | awk '/Mem:/{print $2}')
CPU_CORES=$(nproc)
SYSTEM_DISK_FREE=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')

info "RAM: ${RAM_GB} GB | CPU: ${CPU_CORES} core | Sistem disk bos: ${SYSTEM_DISK_FREE} GB"

[[ $RAM_GB -lt 28 ]] && warn "Minimum 32 GB RAM onerilir (mevcut: ${RAM_GB} GB)"
[[ $CPU_CORES -lt 4 ]] && warn "Minimum 8 CPU core onerilir (mevcut: ${CPU_CORES} core)"
[[ $SYSTEM_DISK_FREE -lt 20 ]] && error "Sistem diskinde en az 20 GB bos alan gerekli!"

# ---- 2. PAKET GUNCELLEME ------------------------------------
step "Sistem guncelleniyor..."
apt-get update -qq
apt-get install -yq \
    apt-transport-https ca-certificates curl gnupg lsb-release \
    git rsync jq python3 parted e2fsprogs ufw

# ---- 3. DOCKER KURULUMU -------------------------------------
step "Docker kuruluyor..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    apt-get install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
    info "Docker kuruldu."
else
    info "Docker zaten yuklu: $(docker --version)"
fi

# docker compose v2 alias
if ! command -v docker-compose &>/dev/null; then
    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null || \
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
fi

# ---- 4. 2. DISK KURULUMU ------------------------------------
step "Veri diski ayarlaniyor: $DATA_DISK -> /data"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -b "$DATA_DISK" ]]; then
    bash "$SCRIPT_DIR/setup-disk.sh" "$DATA_DISK"
else
    warn "$DATA_DISK bulunamadi. Mevcut blok cihazlar:"
    lsblk -d -o NAME,SIZE,TYPE | grep disk
    echo ""
    warn "!!! 2. disk bulunamadi - /data dizini SISTEM DISKINDE olusturuluyor !!!"
    warn "!!! Uretimde mutlaka ayri bir disk kullaniyor olmalisiniz.         !!!"
    mkdir -p /data/{elasticsearch/{data,logs,backups},logstash/{data,logs,filebeat-registry},kibana/data}
    mkdir -p /data/exchange-logs/{message-tracking,iis,httpproxy,mapihttp,smtp-receive,smtp-send}
    chown -R 1000:1000 /data/elasticsearch /data/logstash /data/kibana
fi

# ---- 5. SISTEM TUNING (Elasticsearch icin zorunlu) ----------
step "Sistem limitleri ayarlaniyor..."

# vm.max_map_count (idempotent)
SYSCTL_CONF="/etc/sysctl.d/99-exchange-elk.conf"
cat > "$SYSCTL_CONF" << 'EOF'
# Elasticsearch icin zorunlu
vm.max_map_count=262144
# Network performansi
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
# Swap kullanilmasin (ES icin kritik)
vm.swappiness=1
EOF
sysctl -p "$SYSCTL_CONF"
info "sysctl ayarlari uygulandi."

# Memory limits (idempotent)
LIMITS_CONF="/etc/security/limits.d/99-exchange-elk.conf"
cat > "$LIMITS_CONF" << 'EOF'
# Elasticsearch memory lock
*    soft  memlock  unlimited
*    hard  memlock  unlimited
*    soft  nofile   65536
*    hard  nofile   65536
root soft  memlock  unlimited
root hard  memlock  unlimited
EOF
info "limits.conf ayarlari uygulandi."

# ---- 6. REPO KLONLA / GUNCELLE ------------------------------
step "Repository: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [[ ! -d ".git" ]]; then
    info "Repository klonlaniyor..."
    git clone "$GITHUB_REPO" .
else
    info "Repository guncelleniyor..."
    git pull
fi

# ---- 7. SCRIPT IZINLERI -------------------------------------
chmod +x scripts/*.sh

# ---- 8. FIREWALL --------------------------------------------
step "Firewall kurallari ayarlaniyor..."
if command -v ufw &>/dev/null; then
    ufw --force enable
    ufw allow 22/tcp    comment 'SSH'
    ufw allow 5601/tcp  comment 'Kibana'
    ufw allow 5044/tcp  comment 'Logstash Beats'
    # Elasticsearch ve Logstash API sadece localhost'tan erisim
    ufw deny 9200/tcp
    ufw deny 9600/tcp
    info "Firewall kurallari uygulandi."
fi

# ---- 9. SERVISLERI BASLAT -----------------------------------
step "Docker servisleri baslatiliyor..."
docker-compose up -d

# ---- 10. ILM & INDEX TEMPLATE KUR --------------------------
step "Elasticsearch hazir olana kadar bekleniyor..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s > /dev/null 2>&1; then
        info "Elasticsearch hazir! ($i. deneme)"
        break
    fi
    [[ $i -eq 30 ]] && error "Elasticsearch 150 saniye icinde baslamadi!"
    echo "  Bekleniyor... ($i/30)"
    sleep 5
done

# ILM policy yukle
step "ILM policy uygulamyor..."
bash "$SCRIPT_DIR/setup-ilm.sh"

# ---- 11. KIBANA HAZIR OLANA BEKLENIYOR ----------------------
step "Kibana hazir olana kadar bekleniyor..."
for i in $(seq 1 40); do
    if curl -sf http://localhost:5601/api/status > /dev/null 2>&1; then
        info "Kibana hazir! ($i. deneme)"
        break
    fi
    [[ $i -eq 40 ]] && warn "Kibana 200 saniye icinde baslamadi, index pattern manuel kurulabilir."
    echo "  Bekleniyor... ($i/40)"
    sleep 5
done

# Kibana data views (her index pattern icin ayrı)
for PATTERN in "exchange-msgtrk-*" "exchange-iis-*" "exchange-httpproxy-*" "exchange-mapihttp-*" "exchange-smtp-receive-*" "exchange-smtp-send-*"; do
    NAME=$(echo "$PATTERN" | sed 's/exchange-//;s/-\*//;s/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1))substr($i,2); print}')
    curl -sf -X POST "localhost:5601/api/data_views/data_view" \
        -H "Content-Type: application/json" \
        -H "kbn-xsrf: true" \
        -d "{\"data_view\":{\"title\":\"${PATTERN}\",\"timeFieldName\":\"@timestamp\",\"name\":\"Exchange ${NAME}\"}}" \
        && info "Kibana data view olusturuldu: $PATTERN" || warn "Kibana data view olusturulamadi: $PATTERN"
done

# ---- 12. OZET -----------------------------------------------
step "Deployment tamamlandi!"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "  Kibana         : http://${SERVER_IP}:5601"
echo "  Elasticsearch  : http://${SERVER_IP}:9200  (sadece ic ag)"
echo "  Install Dir    : $INSTALL_DIR"
echo ""
echo "  Disk durumu:"
df -h /data / | column -t
echo ""
echo "  Sonraki adimlar:"
echo "  1. Exchange sunucularda setup-exchange-forwarding.ps1 calistir"
echo "  2. /data/exchange-logs/* dizinine log dosyalarini yonlendir"
echo "  3. Kibana'da dashboards/ icindeki dashboard'u import et"
echo "  4. scripts/health-check.sh ile sistem sagligini kontrol et"