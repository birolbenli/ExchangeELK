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

# Kullanıcı listesi: "kullanici_adi|email|tam_ad"
USERS=(
  "ibrahim.selcuk|ibrahim.selcuk@btcturk.com|Ibrahim Selcuk"
  "serdar.tasdelen|serdar.tasdelen@btcturk.com|Serdar Tasdelen"
  "hakan.salih|hakan.salih@btcturk.com|Hakan Salih"
  "gorkem.yilmaz|gorkem.yilmaz@btcturk.com|Gorkem Yilmaz"
  "dogan.demirkiran|dogan.demirkiran@btcturk.com|Dogan Demirkiran"
)

create_user_and_notify() {
  local USERNAME="$1"
  local EMAIL="$2"
  local FULLNAME="$3"
  # Güvenli rastgele şifre: 16 karakter
  local PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!@#' | head -c 16)

  echo "--- $FULLNAME ($EMAIL) ---"

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
    echo "  ✓ Kullanıcı oluşturuldu: $USERNAME"
  else
    echo "  ✗ Kullanıcı hatası: $RESULT"
    return
  fi

  # Mail gönder
  MAIL_BODY="Merhaba $FULLNAME,

BtcTurk FortiMail Güvenlik İzleme Portalı'na erişim bilgileriniz hazırlandı.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GİRİŞ BİLGİLERİNİZ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
URL       : ${KIBANA_PUBLIC_URL}
Kullanıcı : ${USERNAME}
Şifre     : ${PASSWORD}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Bu portal ne işe yarar?

FortiMail E-posta Güvenlik Kapısı üzerinden geçen tüm e-posta trafiğini
gerçek zamanlı olarak izlemenizi ve analiz etmenizi sağlar.

Portal üzerinde şunları yapabilirsiniz:

📊 E-posta Güvenlik Paneli
  - Son 24 saat / 7 gün / 30 günlük spam, virüs ve auth hatası istatistikleri
  - Saatlik trafik grafiği ve tehdit dağılımı
  - En çok spam gelen domainler ve IP adresleri

🔍 Mesaj Arama Merkezi
  - Gönderen/alıcı adresine, konuya veya tarih aralığına göre mail arama
  - Belirli bir mailin FortiMail tarafından spam/virüs olarak işaretlenip
    işaretlenmediğini görme
  - DKIM, DMARC, SPF kontrol sonuçlarını inceleme
  - Teslim durumu takibi (kabul, red, erteleme)

📈 Log Araştırma Merkezi
  - Ham log verilerine filtreli erişim
  - Belirli IP veya domain üzerinde detaylı analiz
  - Zaman bazlı trend grafiklerini inceleme

⚠️ Önemli bilgiler:
  - Hesabınız salt okunur yetkiye sahiptir (görüntüleme only)
  - Şifrenizi ilk girişin ardından değiştirmeniz önerilir
  - Şifrenizi kimseyle paylaşmayınız
  - Teknik destek için lütfen IT ekibiyle iletişime geçiniz

İyi çalışmalar,
BtcTurk Sistem & Altyapı Ekibi"

  SEND_RESULT=$(curl -s -u "elastic:${ELASTIC_PASS}" -X POST \
    "${KIBANA_URL}/api/actions/connector/${CONNECTOR_ID}/_execute" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d "{
      \"params\": {
        \"to\": [\"${EMAIL}\"],
        \"subject\": \"[BtcTurk] FortiMail İzleme Portalı - Erişim Bilgileriniz\",
        \"message\": $(echo "$MAIL_BODY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
      }
    }")

  if echo "$SEND_RESULT" | grep -q '"status":"ok"'; then
    echo "  ✓ Mail gönderildi: $EMAIL"
  else
    echo "  ✗ Mail hatası: $SEND_RESULT"
  fi
  echo ""
}

echo "=== Kibana Viewer Kullanıcı Kurulumu ==="
echo ""

for USER_ENTRY in "${USERS[@]}"; do
  IFS='|' read -r USERNAME EMAIL FULLNAME <<< "$USER_ENTRY"
  create_user_and_notify "$USERNAME" "$EMAIL" "$FULLNAME"
done

echo "=== Tamamlandı ==="
echo ""
echo "Oluşturulan kullanıcıları listele:"
curl -s -u "elastic:${ELASTIC_PASS}" "${ES_URL}/_security/user" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for u, info in data.items():
  if 'viewer' in info.get('roles', []):
    print(f'  {u:25} {info.get(\"email\",\"-\"):40} roller={info[\"roles\"]}')
"
