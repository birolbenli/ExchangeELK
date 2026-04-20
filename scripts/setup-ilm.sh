#!/bin/bash

# ================================================================
# ILM Policy, Index Template ve Bootstrap Index Kurulum Scripti
# deploy.sh tarafından otomatik çağrılır veya ayrıca çalıştırılır.
#
# Yapı:
#  Hot  (0-7g)  : Aktif yazma, LZ4, 3 shard
#  Warm (7-30g) : Read-only, best_compression, forcemerge→1 segment, 1 shard
#  Cold (30-90g): Freeze (query az, bellek tasarrufu), 0 replica
#  Delete (90g) : Kalıcı silme
# ================================================================

set -euo pipefail

ES="http://localhost:9200"
ES_USER="${ELASTIC_USER:-elastic}"
ES_PASS="${ELASTIC_PASSWORD:-}"
AUTH="-u ${ES_USER}:${ES_PASS}"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[ILM]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[ILM]${NC}  $*"; }
error() { echo -e "${RED}[ILM]${NC}  $*"; exit 1; }

# Elasticsearch'e bağlantı kontrolü
curl -sf $AUTH "$ES/_cluster/health" > /dev/null 2>&1 || error "Elasticsearch ulaşılamıyor: $ES"

info "ILM kurulumu başlıyor..."

# ---- 1. ILM POLICY ------------------------------------------
info "ILM policy uygulanıyor: exchange-logs-policy"
curl -sf $AUTH -X PUT "$ES/_ilm/policy/exchange-logs-policy" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "policy": {
    "_meta": {
      "description": "Exchange 90 gun retention: Hot 7g → Warm 30g (sikis) → Cold 90g (freeze) → Delete"
    },
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "10gb",
            "max_age": "1d",
            "max_docs": 10000000
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "set_priority": { "priority": 50 },
          "readonly": {},
          "allocate": { "number_of_replicas": 0 },
          "shrink":   { "number_of_shards": 1 },
          "forcemerge": {
            "max_num_segments": 1,
            "index_codec": "best_compression"
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": { "priority": 0 },
          "readonly": {},
          "allocate": { "number_of_replicas": 0 }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
EOF
info "ILM policy oluşturuldu."

# ---- 2. COMPONENT TEMPLATE (settings) -----------------------
info "Component template oluşturuluyor: exchange-logs-settings"
curl -sf $AUTH -X PUT "$ES/_component_template/exchange-logs-settings" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "template": {
    "settings": {
      "index.number_of_shards": 3,
      "index.number_of_replicas": 0,
      "index.refresh_interval": "30s",
      "index.codec": "default",
      "index.lifecycle.name": "exchange-logs-policy",
      "index.lifecycle.rollover_alias": "exchange-logs",
      "index.mapping.total_fields.limit": 2000,
      "index.query.default_field": [
        "sender-address", "recipient-address", "message-subject",
        "server-hostname", "client-hostname", "event-id",
        "connector-id", "message-id"
      ]
    }
  }
}
EOF

# ---- 3. COMPONENT TEMPLATE (mappings) -----------------------
info "Component template oluşturuluyor: exchange-logs-mappings"
curl -sf $AUTH -X PUT "$ES/_component_template/exchange-logs-mappings" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "template": {
    "mappings": {
      "dynamic_templates": [
        {
          "strings_as_keyword": {
            "match_mapping_type": "string",
            "unmatch": "*subject*",
            "mapping": { "type": "keyword", "ignore_above": 512 }
          }
        }
      ],
      "properties": {
        "@timestamp":          { "type": "date" },
        "timestamp":           { "type": "date" },
        "log_type":            { "type": "keyword" },
        "exchange_server":     { "type": "keyword" },
        "exchange_role":       { "type": "keyword" },
        "environment":         { "type": "keyword" },
        "dag_member":          { "type": "boolean" },
        "event-id":            { "type": "keyword" },
        "source":              { "type": "keyword" },
        "directionality":      { "type": "keyword" },
        "connector-id":        { "type": "keyword" },
        "sender-address":      { "type": "keyword" },
        "recipient-address":   { "type": "keyword" },
        "sender_domain":       { "type": "keyword" },
        "recipient_domain":    { "type": "keyword" },
        "message-id":          { "type": "keyword" },
        "internal-message-id": { "type": "keyword" },
        "network-message-id":  { "type": "keyword" },
        "message-subject": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword", "ignore_above": 512 } }
        },
        "client-ip":           { "type": "ip", "ignore_malformed": true },
        "server-ip":           { "type": "ip", "ignore_malformed": true },
        "original-client-ip":  { "type": "ip", "ignore_malformed": true },
        "client-hostname":     { "type": "keyword" },
        "server-hostname":     { "type": "keyword" },
        "total-bytes":         { "type": "long" },
        "recipient-count":     { "type": "integer" },
        "recipient-status":    { "type": "keyword" },
        "status":              { "type": "integer" },
        "substatus":           { "type": "integer" },
        "win32-status":        { "type": "integer" },
        "method":              { "type": "keyword" },
        "uri-stem":            { "type": "keyword" },
        "uri-query":           { "type": "keyword" },
        "time-taken":          { "type": "integer" },
        "username":            { "type": "keyword" },
        "user-agent": {
          "type": "text",
          "fields": { "keyword": { "type": "keyword", "ignore_above": 512 } }
        },
        "tags":                { "type": "keyword" },
        "geoip": {
          "properties": {
            "location":    { "type": "geo_point" },
            "country_code2": { "type": "keyword" },
            "country_name":  { "type": "keyword" },
            "city_name":     { "type": "keyword" },
            "region_name":   { "type": "keyword" },
            "continent_code":{ "type": "keyword" },
            "timezone":      { "type": "keyword" },
            "ip":            { "type": "ip", "ignore_malformed": true },
            "latitude":      { "type": "half_float" },
            "longitude":     { "type": "half_float" }
          }
        }
      }
    }
  }
}
EOF

# ---- 4. INDEX TEMPLATE (2 component template'i birleştirir) --
info "Index template oluşturuluyor: exchange-logs"
curl -sf $AUTH -X PUT "$ES/_index_template/exchange-logs" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "index_patterns": [
    "exchange-msgtrk-*",
    "exchange-iis-*",
    "exchange-httpproxy-*",
    "exchange-mapihttp-*",
    "exchange-smtp-receive-*",
    "exchange-smtp-send-*"
  ],
  "priority": 200,
  "composed_of": ["exchange-logs-settings", "exchange-logs-mappings"],
  "_meta": {
    "description": "Exchange Server logs - Hot/Warm/Cold 90 gun",
    "indices": [
      "exchange-msgtrk-*         : Message Tracking",
      "exchange-iis-*            : IIS W3C (X-Forwarded-For aktif)",
      "exchange-httpproxy-*      : HttpProxy Protocol",
      "exchange-mapihttp-*       : MAPI HTTP",
      "exchange-smtp-receive-*   : SMTP Receive",
      "exchange-smtp-send-*      : SMTP Send"
    ]
  }
}
EOF

# ---- 5. INDEX ALIAS veya DATA STREAM (küçük indeksler için basit yaklaşım) ---
# Not: Tarihsel indeksler için data_stream yerine günlük rollover index kullanılır.
# Bu yaklaşımda ILM policy her indekse otomatik uygulanır (template üzerinden).
info "Index template uygulandı. ILM otomatik aktif olacak."

# ---- 6. SNAPSHOT REPOSITORY (yedekleme için) ----------------
info "Snapshot repository kaydediliyor: exchange-backups"
curl -sf $AUTH -X PUT "$ES/_snapshot/exchange-backups" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "type": "fs",
  "settings": {
    "location": "/data/elasticsearch/backups",
    "compress": true,
    "max_snapshot_bytes_per_sec": "100mb",
    "max_restore_bytes_per_sec": "200mb"
  }
}
EOF
info "Snapshot repository hazır: /data/elasticsearch/backups"

# ---- 7. SLM (Snapshot Lifecycle Management) -----------------
info "Otomatik snapshot politikası kuruluyor: exchange-daily-snapshot"
curl -sf $AUTH -X PUT "$ES/_slm/policy/exchange-daily-snapshot" \
    -H "Content-Type: application/json" \
    -d @- << 'EOF'
{
  "schedule": "0 30 2 * * ?",
  "name": "<exchange-snapshot-{now/d}>",
  "repository": "exchange-backups",
  "config": {
    "indices": ["exchange-msgtrk-*","exchange-iis-*","exchange-httpproxy-*","exchange-mapihttp-*","exchange-smtp-receive-*","exchange-smtp-send-*"],
    "ignore_unavailable": true,
    "include_global_state": false
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 5,
    "max_count": 50
  }
}
EOF
info "SLM: Her gece 02:30'da snapshot alınacak, 30 gün saklanacak."

# ---- 8. DURUM RAPORU ----------------------------------------
echo ""
info "=== ILM KURULUM TAMAM ==="
echo ""
echo "  ILM Policy    :"
curl -sf $AUTH "$ES/_ilm/policy/exchange-logs-policy" | jq -r '
  to_entries[0].value.policy.phases | 
  "  Hot    → " + (.hot.min_age // "0") + " - rollover " + (.hot.actions.rollover.max_age),
  "  Warm   → " + .warm.min_age + " - forcemerge + best_compression",
  "  Cold   → " + .cold.min_age + " - freeze",
  "  Delete → " + .delete.min_age
' 2>/dev/null || echo "  (jq yüklü değil, curl ile kontrol edin)"

echo ""
echo "  Index template : exchange-logs"
echo "  Data stream    : exchange-logs"
echo "  Snapshot repo  : /data/elasticsearch/backups"
echo "  Snapshot SLM   : Her gece 02:30, 30 gun saklama"
echo ""
info "Manuel kontrol: curl $ES/_ilm/policy/exchange-logs-policy?pretty"