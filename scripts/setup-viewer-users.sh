#!/bin/bash
# ================================================================
# Kibana Viewer Kullanıcı Oluşturma + Hoşgeldiniz Maili Gönderme
# Çalıştır: bash scripts/setup-viewer-users.sh
# ================================================================

ELASTIC_PASS="${ELASTIC_PASSWORD:-AA12345aa**}"
ES_URL="http://localhost:9200"
KIBANA_URL="http://localhost:5601"
KIBANA_PUBLIC_URL="https://mailtrace.btcturk.local"

# Connector ID'yi otomatik bul
CONNECTOR_ID=$(curl -s -u "elastic:${ELASTIC_PASS}" "${KIBANA_URL}/api/actions/connectors" \
  -H "kbn-xsrf: true" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data:
  if c.get('name') == 'SES Mail Bildirimi':
    print(c['id'])
" 2>/dev/null)

if [ -z "$CONNECTOR_ID" ]; then
  echo "HATA: 'SES Mail Bildirimi' connector bulunamadı. Önce setup-email-connector.sh çalıştırın."
  exit 1
fi
echo "Connector ID: $CONNECTOR_ID"
echo ""

# Kaç kullanıcı ekleneceğini sor
echo ""
read -rp "Kaç kullanıcı eklemek istiyorsunuz? " USER_COUNT

USERS=()
for (( i=1; i<=USER_COUNT; i++ )); do
  echo ""
  echo "── Kullanıcı $i / $USER_COUNT ──────────────────────────"
  read -rp "  Tam ad        : " FULLNAME
  read -rp "  E-posta       : " EMAIL
  # Kullanıcı adını e-postadan otomatik türet (@ öncesi)
  DEFAULT_USERNAME=$(echo "$EMAIL" | cut -d'@' -f1 | tr '.' '.')
  read -rp "  Kullanıcı adı [${DEFAULT_USERNAME}]: " USERNAME
  [ -z "$USERNAME" ] && USERNAME="$DEFAULT_USERNAME"
  USERS+=("${USERNAME}|${EMAIL}|${FULLNAME}")
done

create_user_and_notify() {
  local USERNAME="$1"
  local EMAIL="$2"
  local FULLNAME="$3"

  echo ""
  echo "┌─ $FULLNAME ($EMAIL)"

  # Şifreyi interaktif sor
  while true; do
    read -rsp "│  Şifre girin (boş bırakırsanız otomatik üretilir): " PASSWORD
    echo ""
    if [ -z "$PASSWORD" ]; then
      PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!@#' | head -c 16)
      echo "│  Üretilen şifre: $PASSWORD"
      break
    else
      read -rsp "│  Şifreyi tekrar girin: " PASSWORD2
      echo ""
      if [ "$PASSWORD" = "$PASSWORD2" ]; then
        break
      else
        echo "│  ✗ Şifreler eşleşmedi, tekrar deneyin."
      fi
    fi
  done

  # Kullanıcı oluştur
  RESULT=$(curl -s -u "elastic:${ELASTIC_PASS}" -X PUT "${ES_URL}/_security/user/${USERNAME}" \
    -H "Content-Type: application/json" -d "{
      \"password\": \"${PASSWORD}\",
      \"roles\": [\"viewer\"],
      \"full_name\": \"${FULLNAME}\",
      \"email\": \"${EMAIL}\",
      \"metadata\": { \"created_by\": \"setup-script\" }
    }")

  if echo "$RESULT" | grep -q '"created"'; then
    echo "│  ✓ Kullanıcı oluşturuldu"
  else
    echo "│  ✗ Kullanıcı hatası: $RESULT"
    return
  fi

  # HTML mail içeriği
  MAIL_TEXT="Merhaba ${FULLNAME},

FortiMail izleme portalina erisim bilgileriniz asagidadir.

  Portal   : ${KIBANA_PUBLIC_URL}
  Kullanici: ${USERNAME}
  Sifre    : ${PASSWORD}

Portala giris yaptiktan sonra sifrenizi degistirmeniz onerilir.

---

Portal hakkinda:

FortiMail uzerinden gecen e-posta trafikini gercek zamanli izlemenizi saglar.
Uc ana bolum bulunmaktadir:

  - E-posta Guvenlik Paneli: Spam, virus, auth hatasi istatistikleri ve grafikler
  - Mesaj Arama Merkezi: Gonderici, alici, konu veya tarih araligina gore arama
  - Log Arastirma Merkezi: Ham log analizi, IP/domain bazli detayli inceleme

Hesabiniz salt okunur yetkisine sahip olup yalnizca goruntuleme yapabilirsiniz.
Teknik destek icin IT ekibiyle iletisime geciniz.

BtcTurk Sistem & Altyapi Ekibi"

  SEND_RESULT=$(curl -s -u "elastic:${ELASTIC_PASS}" -X POST \
    "${KIBANA_URL}/api/actions/connector/${CONNECTOR_ID}/_execute" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d "{
      \"params\": {
        \"to\": [\"${EMAIL}\"],
        \"subject\": \"FortiMail Portal - Erisim Bilgileriniz\",
        \"message\": $(echo "$MAIL_TEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
      }
    }")

  if echo "$SEND_RESULT" | grep -q '"status":"ok"'; then
    echo "└  ✓ Mail gönderildi: $EMAIL"
  else
    echo "└  ✗ Mail hatası: $SEND_RESULT"
  fi
}

echo "=== Kibana Viewer Kullanıcı Kurulumu ==="

for USER_ENTRY in "${USERS[@]}"; do
  IFS='|' read -r USERNAME EMAIL FULLNAME <<< "$USER_ENTRY"
  create_user_and_notify "$USERNAME" "$EMAIL" "$FULLNAME"
done

echo ""
echo "=== Tamamlandı ==="
echo ""
echo "Viewer kullanıcıları:"
curl -s -u "elastic:${ELASTIC_PASS}" "${ES_URL}/_security/user" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for u, info in data.items():
  if 'viewer' in info.get('roles', []):
    print(f'  {u:25} {info.get(\"email\",\"-\")}')
"
