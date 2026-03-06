# FortiMail ELK Entegrasyon Rehberi

## Genel Mimari

```
FortiMail Cihazı
      │
      │  Syslog UDP/TCP (port 5514)
      ▼
ELK Sunucusu (Ubuntu)
  └─ Logstash:5514
       └─ pipeline-fortimail.conf
            └─ Elasticsearch: fortimail-{type}-YYYY.MM.dd
                  └─ Kibana: FortiMail - Ana Dashboard
```

---

## 1. FortiMail Üzerinde Yapılacak Adımlar

### 1.1 Web GUI ile Syslog Yapılandırması

1. FortiMail web arayüzüne giriş yapın (https://fortimail-ip)
2. **Log & Report → Log Setting → Remote** menüsüne gidin
3. **New** butonuna tıklayın
4. Aşağıdaki değerleri girin:

| Alan             | Değer                                         |
|-----------------|-----------------------------------------------|
| Status          | Enable                                         |
| Name            | ELK-Logstash                                  |
| IP/FQDN         | `<ELK Sunucu IP>`                             |
| Port            | `5514`                                        |
| Protocol        | `UDP` (veya güvenilirlik için `TCP`)          |
| Log Level       | `Information` (tüm log seviyeleri)            |
| Facility        | `local0`                                      |
| Format          | `Default` (key=value formatı)                 |

5. **Log Types** bölümünde şunları etkinleştirin:
   - [x] **History** (posta trafik logları — en önemli)
   - [x] **Event** (sistem olayları)
   - [x] **Spam** (spam/antispam logları)
   - [x] **Virus** (antivirus tarama logları)
   - [x] **Encrypt** (şifreleme logları — opsiyonel)
   - [x] **DLP** (data loss prevention — opsiyonel)

6. **Apply** ile kaydedin.

---

### 1.2 CLI ile Syslog Yapılandırması (alternatif)

FortiMail SSH'a bağlanın ve şu komutları çalıştırın:

```bash
config log syslogd setting
    set status enable
    set ip <ELK-SUNUCU-IP>
    set port 5514
    set facility local0
    set level information
end

config log syslogd filter
    set history enable
    set event enable
    set virus enable
    set spam enable
    set encrypt enable
end
```

**Yapılandırmayı doğrulayın:**
```bash
get log syslogd setting
diagnose log test
```

---

### 1.3 Firewall / NAT Kuralı

FortiMail ile ELK sunucusu arasında güvenlik duvarı varsa:

| Protokol | Kaynak       | Hedef            | Port | İzin |
|----------|-------------|-----------------|------|------|
| UDP      | FortiMail IP | ELK Sunucu IP   | 5514 | ALLOW |
| TCP      | FortiMail IP | ELK Sunucu IP   | 5514 | ALLOW |

---

## 2. ELK Sunucusunda Yapılacak Adımlar

### 2.1 Docker Compose Güncelleme (zaten yapıldı)

Logstash `docker-compose.yml` dosyasında port 5514 açılmıştır:
```yaml
ports:
  - "5514:5514/udp"   # FortiMail syslog UDP
  - "5514:5514/tcp"   # FortiMail syslog TCP
```

### 2.2 Logstash Pipeline Kontrolü

```bash
# Logstash container'ını yeniden başlatın
cd /opt/exchange-elk
docker compose restart logstash

# Log akışını izleyin
docker logs -f logstash | grep -i fortimail

# Pipeline durumu
curl -s http://localhost:9600/_node/pipelines | python3 -m json.tool | grep -A5 fortimail
```

### 2.3 Syslog Bağlantısını Test Etme

```bash
# UDP test paketi gönder (FortiMail formatını simüle eder)
echo 'date=2024-01-15 time=10:23:45 device_id=FE100C3G12345678 log_id=0200032024 type=history pri=information session_id="test123" client_name="test.example.com" client_ip=1.2.3.4 dst_ip=10.0.0.1 endpoint="SMTP" direction=Incoming from="spam@test.com" to="user@company.com" polid=1 domain="company.com" action=Relay status=Send classifier=Spam mailer=Exchange subject="Test Spam" msg_id="<test@test.com>"' | nc -u localhost 5514

# Elasticsearch'te veriyi doğrula
curl -s "http://localhost:9200/fortimail-*/_search?size=1&sort=@timestamp:desc" | python3 -m json.tool
```

---

## 3. Elasticsearch Index Template (Opsiyonel)

Alanların doğru türlerle (geo_point, keyword vs.) tanımlanması için:

```bash
curl -X PUT "http://localhost:9200/_index_template/fortimail-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["fortimail-*"],
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "exchange-ilm-policy",
        "refresh_interval": "10s"
      },
      "mappings": {
        "dynamic_templates": [
          {
            "strings_as_keyword": {
              "match_mapping_type": "string",
              "mapping": { "type": "keyword", "ignore_above": 512 }
            }
          }
        ],
        "properties": {
          "@timestamp":    { "type": "date" },
          "from_addr":     { "type": "keyword" },
          "to_addr":       { "type": "keyword" },
          "from_domain":   { "type": "keyword" },
          "to_domain":     { "type": "keyword" },
          "subject":       { "type": "text", "fields": { "keyword": { "type": "keyword", "ignore_above": 512 } } },
          "client_ip":     { "type": "ip" },
          "dst_ip":        { "type": "ip" },
          "action":        { "type": "keyword" },
          "status":        { "type": "keyword" },
          "direction":     { "type": "keyword" },
          "classifier":    { "type": "keyword" },
          "log_type":      { "type": "keyword" },
          "severity":      { "type": "keyword" },
          "virus_name":    { "type": "keyword" },
          "policy_id":     { "type": "integer" },
          "bandwidth":     { "type": "long" },
          "sess_duration": { "type": "integer" },
          "session_id":    { "type": "keyword" },
          "msg_id":        { "type": "keyword" },
          "device_id":     { "type": "keyword" },
          "domain":        { "type": "keyword" },
          "mailer":        { "type": "keyword" },
          "geoip": {
            "properties": {
              "location":       { "type": "geo_point" },
              "country_name":   { "type": "keyword" },
              "country_code2":  { "type": "keyword" },
              "city_name":      { "type": "keyword" },
              "region_name":    { "type": "keyword" },
              "coordinates":    { "type": "float" }
            }
          }
        }
      }
    }
  }'
```

---

## 4. Kibana Dashboard Kurulumu

### 4.1 NDJSON Import

1. Kibana'ya gidin: **http://ELK-IP:5601**
2. **Management → Stack Management → Saved Objects** menüsünü açın
3. **Import** butonuna tıklayın
4. `dashboards/fortimail-dashboard.ndjson` dosyasını seçin
5. **Import** ile onaylayın

### 4.2 Dashboard Erişimi

Import sonrası **Dashboards** menüsünde şunlar görünür:

- **FortiMail - Ana Dashboard** — genel bakış, istatistikler ve tüm paneller

Saved Search'ler (**Discover** menüsünde):
- **FortiMail - Posta Arama** — history logları, tüm sütunlar
- **FortiMail - Engellenen Mesajlar** — Reject/Block/Discard filtreli
- **FortiMail - Spam Loglar** — Spam/Bulk sınıflandırılanlar

---

## 5. Dashboard Panel Açıklamaları

| Panel | Açıklama |
|-------|----------|
| Toplam FortiMail Kaydı | Seçili zaman aralığındaki tüm log sayısı |
| Gelen Posta (Inbound) | direction=Incoming logları |
| Engellenen / Reddedilen | Reject + Block + Discard toplamı |
| Spam / Bulk Tespit | classifier=Spam veya Bulk logları |
| Virus Tespit | log_type=virus logları |
| **Arama Filtreleri** | Gonderen, Alıcı, Konu, Eylem, Sınıflandırıcı, Kaynak IP — interaktif filtre |
| Trafik Zaman Serisi | Gelen / Giden / Engellenen / Spam zaman serisi histogram |
| Eylem Dağılımı | Relay / Reject / Discard / Block pasta grafik |
| Yön Dağılımı | Inbound / Outbound pasta grafik |
| Sınıflandırıcı | Normal / Spam / Bulk / Virus dağılımı |
| Log Türü | history / event / spam / virus dağılımı |
| En Çok Gönderen | Tablo: gönderici adresleri |
| En Çok Alan | Tablo: alıcı adresleri |
| En Çok Engellenen IP | Tablo: engellenen kaynak IP + ülke |
| En Çok Spam Gelen Domain | Spam gönderen kaynak domainler |
| Tespit Edilen Virüsler | Virüs adı + kaynak tablo |
| Policy Bazlı Trafik | Policy ID + Eylem çapraz tablo |
| Coğrafi Harita | Kaynak IP dağılımı dünya haritası |

---

## 6. Mesaj / Log Arama (KQL Örnekleri)

Kibana Discover veya Dashboard search bar'da şu sorgular kullanılabilir:

```kql
# Belirli göndericiden gelen tüm mesajlar
from_addr: "user@external.com"

# Belirli alıcıya gelen mesajlar
to_addr: "ceo@company.com"

# Konu içinde kelime arama (wildcard)
subject: *invoice*

# Spam + belirli domain
classifier: Spam AND from_domain: "suspicious.com"

# Engellenen mesajlar + ülke
action: Reject AND geoip.country_name: "Russia"

# Virüs tespiti
log_type: virus AND virus_name: *

# Belirli client IP'den gelen
client_ip: "1.2.3.4"

# Outbound ve policy bazlı
direction: Outgoing AND policy_id: 3

# Zaman aralığında spam
classifier: Spam AND @timestamp:[2024-01-01 TO 2024-01-31]

# Session ID ile tüm olaylar
session_id: "abc12345"
```

---

## 7. FortiMail Log Alanları Referansı

| FortiMail Alanı | ELK Alanı      | Açıklama |
|----------------|---------------|----------|
| type           | log_type      | history / event / spam / virus / encrypt |
| pri            | severity      | information / warning / error / critical |
| device_id      | device_id     | FortiMail donanım seri numarası |
| direction      | direction     | Incoming / Outgoing |
| from           | from_addr     | Gönderici e-posta adresi |
| to             | to_addr       | Alıcı e-posta adresi |
| subject        | subject       | E-posta konusu |
| client_ip      | client_ip     | Gönderen SMTP sunucusu IP |
| dst_ip         | dst_ip        | Hedef IP |
| action         | action        | Relay / Reject / Discard / Block |
| status         | status        | Send / Reject / Failed |
| classifier     | classifier    | Normal / Spam / Bulk / Virus |
| polid          | policy_id     | Uygulanan policy numarası |
| domain         | domain        | Alıcı domain |
| mailer         | mailer        | Exchange / Other |
| msg_id         | msg_id        | Mesaj ID (Message-ID başlığı) |
| session_id     | session_id    | SMTP oturum ID |
| virus          | virus_name    | Tespit edilen virüs adı |
| sess_duration  | sess_duration | Oturum süresi (saniye) |
| bandwidth      | bandwidth     | Transfer boyutu (byte) |
| —              | from_domain   | from_addr'den çıkarılan domain |
| —              | to_domain     | to_addr'den çıkarılan domain |
| —              | geoip.*       | client_ip GeoIP verileri |

---

## 8. ILM / Index Yaşam Döngüsü

Mevcut `exchange-ilm-policy` policy'sini FortiMail index'lerine uygulamak için:

```bash
# fortimail-* index'lerini mevcut ILM policy'sine ekle
curl -X PUT "http://localhost:9200/_index_template/fortimail-template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["fortimail-*"],
    "template": {
      "settings": {
        "index.lifecycle.name": "exchange-ilm-policy"
      }
    }
  }'
```

---

## 9. Sorun Giderme

```bash
# Logstash fortimail pipeline logları
docker logs logstash 2>&1 | grep -i "fortimail\|5514\|syslog"

# Port 5514 dinleniyor mu?
docker exec logstash ss -ulnp | grep 5514
docker exec logstash ss -tlnp | grep 5514

# Elasticsearch'te FortiMail index'leri var mı?
curl -s "http://localhost:9200/_cat/indices/fortimail-*?v"

# Son 5 log kaydını göster
curl -s "http://localhost:9200/fortimail-*/_search?size=5&sort=@timestamp:desc&pretty"

# Dead Letter Queue'da log var mı?
docker exec logstash ls /usr/share/logstash/data/dead_letter_queue/fortimail/
```

### Sık Karşılaşılan Sorunlar

| Sorun | Çözüm |
|-------|-------|
| Port 5514'e bağlantı gelmiyor | `docker-compose.yml`'de `5514:5514/udp` olduğunu doğrulayın; host firewall kontrol edin |
| `_fm_not_fortimail` tag | Gelen log FortiMail KV formatında değil; syslog format ayarını kontrol edin |
| `@timestamp` yanlış | FortiMail `date`/`time` alanı gelmiyor; timezone ayarı kontrol edin |
| Kibana'da index göremedim | Dashboard import öncesi en az 1 log gelmiş olmalı; index pattern'ı manuel oluşturun |
| GeoIP çalışmıyor | `geoip` klasöründe GeoLite2-City.mmdb dosyasının varlığını kontrol edin |
