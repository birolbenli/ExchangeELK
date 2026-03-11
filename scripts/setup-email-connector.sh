#!/bin/bash
# ================================================================
# Amazon SES Email Connector Kurulumu
# Çalıştır: bash scripts/setup-email-connector.sh
# Credentials .env dosyasından okunur (git'e gitmez)
# ================================================================

# .env dosyasından yükle
if [ -f /opt/exchange-elk/.env ]; then
  export $(grep -E '^SMTP_|^ELASTIC_PASSWORD' /opt/exchange-elk/.env | xargs)
fi

ELASTIC_PASS="${ELASTIC_PASSWORD:-AA12345aa**}"
KIBANA_URL="http://localhost:5601"

if [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASSWORD" ]; then
  echo "HATA: SMTP_USER veya SMTP_PASSWORD .env dosyasında bulunamadı."
  echo "Lütfen .env dosyasına şu satırları ekleyin:"
  echo "  SMTP_USER=<aws_access_key>"
  echo "  SMTP_PASSWORD=<aws_smtp_password>"
  exit 1
fi

echo "=== Amazon SES Email Connector Kurulumu ==="

# Mevcut connector'ı sil (varsa)
EXISTING=$(curl -s -u "elastic:${ELASTIC_PASS}" "${KIBANA_URL}/api/actions/connectors" \
  -H "kbn-xsrf: true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data:
  if c.get('id') == 'ses-alert-email':
    print(c['id'])
" 2>/dev/null)

if [ -n "$EXISTING" ]; then
  echo "Mevcut connector siliniyor..."
  curl -s -u "elastic:${ELASTIC_PASS}" -X DELETE \
    "${KIBANA_URL}/api/actions/connector/ses-alert-email" \
    -H "kbn-xsrf: true" > /dev/null
fi

# Connector oluştur
echo "Connector oluşturuluyor..."
RESULT=$(curl -s -u "elastic:${ELASTIC_PASS}" -X POST \
  "${KIBANA_URL}/api/actions/connector/ses-alert-email" \
  -H "Content-Type: application/json" \
  -H "kbn-xsrf: true" \
  -d "{
    \"name\": \"SES Mail Bildirimi\",
    \"connector_type_id\": \".email\",
    \"config\": {
      \"from\": \"mailtrace@alert.btcturk.com\",
      \"host\": \"email-smtp.eu-west-1.amazonaws.com\",
      \"port\": 587,
      \"secure\": false
    },
    \"secrets\": {
      \"user\": \"${SMTP_USER}\",
      \"password\": \"${SMTP_PASSWORD}\"
    }
  }")

echo "$RESULT" | python3 -m json.tool 2>/dev/null | grep -E '"id"|"name"|"connector_type"'

if echo "$RESULT" | grep -q '"id"'; then
  echo ""
  echo "✓ Connector başarıyla oluşturuldu."
else
  echo ""
  echo "✗ Hata oluştu:"
  echo "$RESULT"
fi
