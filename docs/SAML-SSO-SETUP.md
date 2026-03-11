# Kibana SAML SSO - Microsoft Entra ID Entegrasyon Rehberi

## Genel Bakış

| Parametre | Değer |
|-----------|-------|
| **Kibana URL** | `https://mailtrace.btcturk.local` |
| **Tenant ID** | `c4c34dec-4224-42e4-9deb-24bee4551281` |
| **SP Entity ID** | `kibana-exchange-elk` |
| **ACS (Reply) URL** | `https://mailtrace.btcturk.local/api/security/saml/callback` |
| **Logout URL** | `https://mailtrace.btcturk.local/logout` |
| **IdP Metadata URL** | `https://login.microsoftonline.com/c4c34dec-4224-42e4-9deb-24bee4551281/federationmetadata/2007-06/federationmetadata.xml` |

---

## Adım 1: Entra ID'de Enterprise Application Oluştur

1. **Azure Portal** → **Microsoft Entra ID** → **Enterprise Applications**
2. **+ New application** → **+ Create your own application**
3. İsim: `Kibana Exchange ELK`
4. **Integrate any other application you don't find in the gallery** seçip **Create**

---

## Adım 2: SAML Konfigürasyonu

1. Uygulama sayfasında → **Single sign-on** → **SAML** seç
2. **Basic SAML Configuration** düzenle:

   | Alan | Değer |
   |------|-------|
   | Identifier (Entity ID) | `kibana-exchange-elk` |
   | Reply URL (ACS URL) | `https://mailtrace.btcturk.local/api/security/saml/callback` |
   | Sign on URL | `https://mailtrace.btcturk.local` |
   | Logout URL | `https://mailtrace.btcturk.local/logout` |

3. **Attributes & Claims** düzenle (varsayılanlar yeterli, ek olarak ekle):

   | Claim name | Source attribute |
   |-----------|-----------------|
   | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | `user.userprincipalname` |
   | `http://schemas.microsoft.com/identity/claims/displayname` | `user.displayname` |
   | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress` | `user.mail` |
   | `http://schemas.microsoft.com/ws/2008/06/identity/claims/groups` | `user.groups [All]` |

4. **SAML Certificates** bölümünden **Federation Metadata XML** → **Download** et

---

## Adım 3: Metadata Dosyasını Sunucuya Yükle

İndirilen XML dosyasını sunucuya kopyala:

```bash
# Windows'tan Ubuntu'ya SCP ile kopyala
scp federationmetadata.xml root@eqlpexcelk01:/opt/exchange-elk/elasticsearch/config/saml/entra-metadata.xml
```

VEYA doğrudan Ubuntu'da indir:

```bash
curl -o /opt/exchange-elk/elasticsearch/config/saml/entra-metadata.xml \
  "https://login.microsoftonline.com/c4c34dec-4224-42e4-9deb-24bee4551281/federationmetadata/2007-06/federationmetadata.xml"
```

---

## Adım 4: Kullanıcı/Grup Atama

1. Entra ID uygulamasında → **Users and groups** → **+ Add user/group**
2. Kibana'ya erişmesini istediğiniz kullanıcı veya grupları ekleyin

---

## Adım 5: Stack'i Yeniden Başlat

```bash
cd /opt/exchange-elk
git pull
docker compose down
docker compose up -d
```

Başlangıç için biraz bekleyin:
```bash
docker compose ps
```

---

## Adım 6: Role Mapping Kur

```bash
bash scripts/setup-saml-roles.sh
```

Bu script:
- Tüm Entra ID kullanıcılarına `kibana_admin` rolü atar
- Group Object ID girerseniz o gruba `superuser` rolü atar

---

## Adım 7: Test

1. Tarayıcıda yeni sekme (incognito) açın
2. `https://mailtrace.btcturk.local` adresine gidin
3. **"Microsoft Entra ID ile Giriş"** butonuna tıklayın
4. Entra hesabınızla oturum açın

---

## Sorun Giderme

### "Realm not found" hatası
→ elasticsearch.yml'de `saml1` realm adı ile kibana.yml'de `realm: saml1` eşleşmeli

### "Invalid signature" hatası
→ Metadata XML dosyasının güncel olduğunu kontrol edin

### "No groups attribute" uyarısı (sorun değil)
→ Groups claim'i Entra'da yapılandırılmamışsa `attributes.groups` satırını kaldırın

### Entra metadata URL'ye erişilemiyor
→ Ubuntu sunucu `login.microsoftonline.com`'a çıkabilmeli:
```bash
curl -I https://login.microsoftonline.com
```

---

## local Kibana hesabıyla yedek giriş

SAML çalışmasa bile `basic.basic1` provider aktif:
- `https://mailtrace.btcturk.local/login?next=%2F` adresine gidin
- **"Kibana hesabı ile giriş"** linkine tıklayın
- `elastic / AA12345aa**` ile giriş yapın
