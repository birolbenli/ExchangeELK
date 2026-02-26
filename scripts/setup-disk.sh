#!/bin/bash

# ============================================================
# 2. Disk Kurulum Scripti
# Exchange ELK Stack - Tüm veriler sistem diskine yazılmaz.
# /dev/sdb (2. disk) /data altına mount edilir.
# Bu script deploy.sh'den önce VEYA deploy.sh tarafından çağrılır.
# ============================================================

set -euo pipefail

DATA_DISK="${1:-/dev/sdb}"   # Argüman verilmezse /dev/sdb kabul edilir
MOUNT_POINT="/data"
FSTAB_ENTRY_MARKER="# exchange-elk-data-disk"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Root kontrolü
[[ "$EUID" -ne 0 ]] && error "Bu script root veya sudo ile çalıştırılmalıdır."

info "Hedef disk: $DATA_DISK"

# Disk mevcut mu?
if [[ ! -b "$DATA_DISK" ]]; then
    error "Disk bulunamadı: $DATA_DISK\nMevcut diskler:\n$(lsblk -d -o NAME,SIZE,TYPE)"
fi

# Disk zaten mount edilmiş mi?
if mount | grep -q "$DATA_DISK"; then
    warn "$DATA_DISK zaten mount edilmiş:"
    mount | grep "$DATA_DISK"
    info "Mevcut mount kullanılıyor, yeniden formatlanmıyor."
else
    # Disk boyutunu göster
    DISK_SIZE=$(lsblk -d -o SIZE -n "$DATA_DISK" | xargs)
    info "Disk boyutu: $DISK_SIZE"

    # Onay iste
    echo ""
    warn "DİKKAT: $DATA_DISK diski sıfırdan formatlanacak, tüm mevcut veri silinecek!"
    read -rp "Devam etmek istiyor musunuz? (yes/no): " CONFIRM
    [[ "$CONFIRM" != "yes" ]] && error "İşlem iptal edildi."

    # Partition oluştur
    info "GPT partition tablosu oluşturuluyor..."
    parted -s "$DATA_DISK" mklabel gpt
    parted -s "$DATA_DISK" mkpart primary ext4 0% 100%

    # Partition ismi (sdb → sdb1, nvme0n1 → nvme0n1p1)
    if [[ "$DATA_DISK" =~ nvme ]]; then
        PARTITION="${DATA_DISK}p1"
    else
        PARTITION="${DATA_DISK}1"
    fi

    # Kısa bekleme (udev)
    sleep 2

    # ext4 formatla
    info "ext4 olarak formatlanıyor: $PARTITION"
    mkfs.ext4 -F -L "elk-data" "$PARTITION"

    # UUID al
    UUID=$(blkid -s UUID -o value "$PARTITION")
    info "Disk UUID: $UUID"

    # Mount point oluştur
    mkdir -p "$MOUNT_POINT"

    # fstab'a ekle (idempotent)
    if grep -q "$FSTAB_ENTRY_MARKER" /etc/fstab; then
        warn "fstab kaydı zaten mevcut, geçiliyor."
    else
        info "fstab'a ekleniyor..."
        echo "" >> /etc/fstab
        echo "$FSTAB_ENTRY_MARKER" >> /etc/fstab
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults,noatime,nofail 0 2" >> /etc/fstab
    fi

    # Mount et
    info "Disk mount ediliyor: $MOUNT_POINT"
    mount "$MOUNT_POINT"
fi

# ----------------------------------------------------------
# Dizin yapısını oluştur
# ----------------------------------------------------------
info "Veri dizinleri oluşturuluyor..."

declare -A DIRS=(
    ["elasticsearch/data"]="1000:1000"      # elasticsearch user UID:GID
    ["elasticsearch/logs"]="1000:1000"
    ["elasticsearch/backups"]="1000:1000"
    ["logstash/data"]="1000:1000"
    ["logstash/logs"]="1000:1000"
    ["logstash/filebeat-registry"]="root:root"
    ["kibana/data"]="1000:1000"
    ["exchange-logs/message-tracking"]="root:root"
    ["exchange-logs/iis"]="root:root"
    ["exchange-logs/httpproxy"]="root:root"
    ["exchange-logs/mapihttp"]="root:root"
    ["exchange-logs/smtp-receive"]="root:root"
    ["exchange-logs/smtp-send"]="root:root"
    ["docker"]="root:root"
)

for DIR in "${!DIRS[@]}"; do
    OWNER="${DIRS[$DIR]}"
    FULL_PATH="$MOUNT_POINT/$DIR"
    mkdir -p "$FULL_PATH"
    chown "$OWNER" "$FULL_PATH" 2>/dev/null || true
    chmod 755 "$FULL_PATH"
done

# ----------------------------------------------------------
# Docker data-root'u 2. diske taşı
# ----------------------------------------------------------
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

if systemctl is-active --quiet docker 2>/dev/null; then
    CURRENT_ROOT=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    if [[ "$CURRENT_ROOT" != "$MOUNT_POINT/docker" ]]; then
        info "Docker data-root $MOUNT_POINT/docker'a taşınıyor..."
        systemctl stop docker

        # Mevcut Docker verisini taşı (images, volumes korunsun)
        if [[ -d /var/lib/docker ]] && [[ "$(ls -A /var/lib/docker 2>/dev/null)" ]]; then
            warn "Mevcut Docker verisi /var/lib/docker → $MOUNT_POINT/docker kopyalanıyor (bu işlem uzun sürebilir)..."
            rsync -aP /var/lib/docker/ "$MOUNT_POINT/docker/"
        fi

        # daemon.json güncelle
        mkdir -p "$(dirname $DOCKER_DAEMON_JSON)"
        if [[ -f "$DOCKER_DAEMON_JSON" ]]; then
            python3 -c "
import json, sys
with open('$DOCKER_DAEMON_JSON') as f:
    d = json.load(f)
d['data-root'] = '$MOUNT_POINT/docker'
with open('$DOCKER_DAEMON_JSON', 'w') as f:
    json.dump(d, f, indent=2)
"
        else
            echo "{\"data-root\": \"$MOUNT_POINT/docker\"}" > "$DOCKER_DAEMON_JSON"
        fi

        systemctl start docker
        info "Docker yeniden başlatıldı, yeni data-root: $MOUNT_POINT/docker"
    else
        info "Docker data-root zaten $MOUNT_POINT/docker'da."
    fi
else
    # Docker henüz kurulmamış, sadece daemon.json oluştur
    mkdir -p "$(dirname $DOCKER_DAEMON_JSON)"
    if [[ ! -f "$DOCKER_DAEMON_JSON" ]]; then
        echo "{\"data-root\": \"$MOUNT_POINT/docker\"}" > "$DOCKER_DAEMON_JSON"
        info "Docker daemon.json oluşturuldu (data-root: $MOUNT_POINT/docker)"
    fi
fi

# ----------------------------------------------------------
# Disk kullanım özeti
# ----------------------------------------------------------
info ""
info "=== DİSK KURULUM TAMAMLANDI ==="
df -hT "$MOUNT_POINT"
echo ""
info "Mount noktası : $MOUNT_POINT"
info "Dizin yapısı  :"
find "$MOUNT_POINT" -maxdepth 2 -type d | sort | sed 's|'"$MOUNT_POINT"'||' | awk '{print "  /data" $0}'
echo ""
info "fstab kaydı:"
grep -A1 "$FSTAB_ENTRY_MARKER" /etc/fstab
echo ""
warn "Sunucuyu yeniden başlattıktan sonra disk otomatik mount edilecektir."