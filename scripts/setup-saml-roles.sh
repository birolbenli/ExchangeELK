#!/bin/bash
# ================================================================
# Entra ID SAML - Kibana Role Mapping Kurulumu
# Kullanım: bash setup-saml-roles.sh
# ================================================================

ELASTIC_PASS="${ELASTIC_PASSWORD:-AA12345aa**}"
ES_URL="http://localhost:9200"

echo "=== Kibana SAML Role Mapping Kurulumu ==="

# 1. superuser rolü: tüm Entra ID kullanıcıları (realm bazlı)
echo ""
echo "[1/2] Entra ID kullanıcılarına 'kibana_admin' rolü atanıyor..."
curl -s -u "elastic:${ELASTIC_PASS}" -X PUT "${ES_URL}/_security/role_mapping/entra_kibana_admin" \
  -H "Content-Type: application/json" -d '{
    "roles": ["kibana_admin"],
    "enabled": true,
    "rules": {
      "field": { "realm.name": "saml1" }
    },
    "metadata": { "version": 1 }
  }' | python3 -m json.tool

# 2. superuser rolü: belirli bir Entra grup (Group Object ID ile)
# Entra ID'den grup Object ID al: Azure Portal → Groups → <grup> → Object ID
echo ""
echo "[2/2] Entra grubuna 'superuser' rolü atanıyor (isteğe bağlı, group object id giriniz)..."
echo "    Entra Group Object ID girin (boş bırakın atlamak için):"
read -r GROUP_ID
if [ -n "$GROUP_ID" ]; then
  curl -s -u "elastic:${ELASTIC_PASS}" -X PUT "${ES_URL}/_security/role_mapping/entra_superuser_group" \
    -H "Content-Type: application/json" -d "{
      \"roles\": [\"superuser\"],
      \"enabled\": true,
      \"rules\": {
        \"all\": [
          { \"field\": { \"realm.name\": \"saml1\" } },
          { \"field\": { \"groups\": \"${GROUP_ID}\" } }
        ]
      },
      \"metadata\": { \"version\": 1 }
    }" | python3 -m json.tool
fi

# 3. Mevcut role mapping'leri listele
echo ""
echo "=== Aktif Role Mapping'ler ==="
curl -s -u "elastic:${ELASTIC_PASS}" "${ES_URL}/_security/role_mapping" | python3 -m json.tool | grep -E '"(enabled|roles|realm)"'

echo ""
echo "=== Kurulum Tamamlandı ==="
