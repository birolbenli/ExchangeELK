#!/bin/bash
# Logstash persistent queue kurtarma.
# Domain join / reboot sonrası 5044 refuse veya pipeline takılırsa:
#   sudo ./scripts/reset-logstash-queues.sh
set -euo pipefail
cd /opt/exchange-elk 2>/dev/null || cd "$(dirname "$0")/.."

echo "Logstash durduruluyor..."
docker compose stop logstash

echo "PQ / DLQ temizleniyor: /data/logstash/data/queue / dead_letter_queue"
rm -rf /data/logstash/data/queue /data/logstash/data/dead_letter_queue
mkdir -p /data/logstash/data
chown -R 1000:1000 /data/logstash/data 2>/dev/null || true

echo "Logstash baslatiliyor..."
docker compose up -d logstash
echo "Hazir. Kontrol: curl -s http://localhost:9600/_node/stats/pipelines | python3 -m json.tool"
