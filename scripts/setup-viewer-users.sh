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
  HTML_BODY="<html><body style='font-family:Arial,sans-serif;color:#222;max-width:600px;margin:0 auto'>
<div style='background:#1a1a2e;padding:24px 32px;border-radius:8px 8px 0 0'>
  <h2 style='color:#fff;margin:0'>BtcTurk</h2>
  <p style='color:#aaa;margin:4px 0 0'>FortiMail Güvenlik İzleme Portalı</p>
</div>
<div style='border:1px solid #e0e0e0;border-top:none;padding:32px;border-radius:0 0 8px 8px'>
  <p>Merhaba <strong>${FULLNAME}</strong>,</p>
  <p>FortiMail Güvenlik İzleme Portalı'na erişim bilgileriniz aşağıda yer almaktadır.</p>

  <table style='width:100%;background:#f5f7ff;border-radius:8px;padding:20px;border-collapse:collapse;margin:24px 0'>
    <tr><td style='padding:8px 16px;color:#666;width:120px'>URL</td>
        <td style='padding:8px 16px'><a href='${KIBANA_PUBLIC_URL}' style='color:#4a6cf7;font-weight:bold'>${KIBANA_PUBLIC_URL}</a></td></tr>
    <tr><td style='padding:8px 16px;color:#666'>Kullanıcı</td>
        <td style='padding:8px 16px'><strong>${USERNAME}</strong></td></tr>
    <tr><td style='padding:8px 16px;color:#666'>Şifre</td>
        <td style='padding:8px 16px'><code style='background:#e8ecff;padding:4px 10px;border-radius:4px;letter-spacing:1px'>${PASSWORD}</code></td></tr>
  </table>

  <h3 style='color:#1a1a2e;border-bottom:2px solid #4a6cf7;padding-bottom:8px'>Bu portal ne işe yarar?</h3>
  <p>FortiMail E-posta Güvenlik Kapısı üzerinden geçen tüm e-posta trafiğini gerçek zamanlı olarak izlemenizi ve analiz etmenizi sağlar.</p>

  <h4 style='color:#4a6cf7;margin-bottom:6px'>📊 E-posta Güvenlik Paneli</h4>
  <ul style='margin:0 0 16px;padding-left:20px;line-height:1.8'>
    <li>Son 24 saat / 7 gün / 30 günlük spam, virüs ve auth hatası istatistikleri</li>
    <li>Saatlik trafik grafiği ve tehdit dağılımı</li>
    <li>En çok spam gelen domainler ve IP adresleri</li>
  </ul>

  <h4 style='color:#4a6cf7;margin-bottom:6px'>🔍 Mesaj Arama Merkezi</h4>
  <ul style='margin:0 0 16px;padding-left:20px;line-height:1.8'>
    <li>Gönderen/alıcı adresine, konuya veya tarih aralığına göre mail arama</li>
    <li>Mailin spam/virüs olarak işaretlenip işaretlenmediğini görme</li>
    <li>DKIM, DMARC, SPF kontrol sonuçlarını inceleme</li>
    <li>Teslim durumu takibi (kabul, red, erteleme)</li>
  </ul>

  <h4 style='color:#4a6cf7;margin-bottom:6px'>📈 Log Araştırma Merkezi</h4>
  <ul style='margin:0 0 16px;padding-left:20px;line-height:1.8'>
    <li>Ham log verilerine filtreli erişim</li>
    <li>Belirli IP veya domain üzerinde detaylı analiz</li>
    <li>Zaman bazlı trend grafiklerini inceleme</li>
  </ul>

  <div style='background:#fff8e1;border-left:4px solid #ffc107;padding:16px;border-radius:4px;margin-top:24px'>
    <strong>⚠️ Önemli bilgiler:</strong>
    <ul style='margin:8px 0 0;padding-left:20px;line-height:1.8'>
      <li>Hesabınız <strong>salt okunur</strong> yetkiye sahiptir (görüntüleme only)</li>
      <li>Şifrenizi ilk girişin ardından değiştirmeniz önerilir</li>
      <li>Şifrenizi kimseyle paylaşmayınız</li>
      <li>Teknik destek için IT ekibiyle iletişime geçiniz</li>
    </ul>
  </div>

  <p style='margin-top:32px;color:#888;font-size:13px'>İyi çalışmalar,<br><strong>BtcTurk Sistem &amp; Altyapı Ekibi</strong></p>
</div>
</body></html>"

  SEND_RESULT=$(curl -s -u "elastic:${ELASTIC_PASS}" -X POST \
    "${KIBANA_URL}/api/actions/connector/${CONNECTOR_ID}/_execute" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d "{
      \"params\": {
        \"to\": [\"${EMAIL}\"],
        \"subject\": \"[BtcTurk] FortiMail İzleme Portalı - Erişim Bilgileriniz\",
        \"message\": \"Lütfen HTML destekli bir e-posta istemcisi kullanın.\",
        \"messageHTML\": $(echo "$HTML_BODY" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
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
