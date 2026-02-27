# Exchange Server DAG - ELK Stack Log Analiz Sistemi

600 mailbox kapasiteli Exchange Server DAG ortami icin log toplama, isleme ve gorsellestirme sistemi.
ELK 8.11.1 -- Docker Compose -- Ubuntu 22.04 LTS

---

## Sistem Gereksinimleri

| Bilesen | Minimum | Onerilen |
|---------|---------|----------|
| RAM | 24 GB | 32 GB |
| CPU | 6 Core | 8 Core |
| Sistem Diski | 60 GB SSD | 100 GB SSD (yalnizca OS + Docker) |
| Data Diski | 1 TB SSD | 2 TB SSD/NVMe |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

Elasticsearch, Logstash ve tum log verileri sistem diskine degil ikinci diske (`/data`) yazilir.

### Disk Kullanim Projeksiyonu (600 Mailbox, 90 Gun Retention)

```
Gunluk ham log uretimi:
  Message Tracking : ~2 GB/gun
  IIS Logs         : ~1 GB/gun
  SMTP Logs        : ~500 MB/gun
  Toplam ham       : ~3.5 GB/gun

90 gunluk ham veri: ~315 GB

ILM + sikistirma sonrasi Elasticsearch kullanimi:
  Hot  (0-7g)   : ~28 GB   - LZ4, 3 shard
  Warm (7-30g)  : ~46 GB   - best_compression + forcemerge
  Cold (30-90g) : ~72 GB   - freeze
  Toplam ES     : ~146 GB

Toplam /data kullanimi (snapshot dahil): ~211 GB
```

---

## Kurulum

### 1. Ubuntu Sunucuya Deploy

```bash
git clone https://github.com/birolbenli/ExchangeELK.git /opt/exchange-elk
cd /opt/exchange-elk
chmod +x scripts/*.sh

# 2. diski hazirla ve tum servisleri baslat
sudo ./scripts/deploy.sh https://github.com/birolbenli/ExchangeELK.git /dev/sdb
```

`deploy.sh` adimlari: disk partition ve mount, Docker kurulumu, data dizinleri, ILM/template, container baslat, dashboard import.

Yalnizca ILM'yi yeniden uygulamak icin:
```bash
sudo ./scripts/setup-ilm.sh
```

### 2. GeoIP Veritabani

Harita ozelligi icin MaxMind GeoLite2-City veritabani gereklidir. Deploy sonrasi:

```bash
mkdir -p /opt/exchange-elk/logstash/geoip
curl -L "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb" \
  -o /opt/exchange-elk/logstash/geoip/GeoLite2-City.mmdb
docker compose restart logstash
```

### 3. Exchange Sunucularda Filebeat Kurulumu

Her Exchange Server'da PowerShell (yonetici) ile:

```powershell
.\scripts\setup-exchange-forwarding.ps1 -ELKServerIP "10.11.12.19" -InstallFilebeatAgent
```

Script sunlari yapar: Filebeat indir/kur, `filebeat.yml` yaz (`output.logstash.hosts`), servis olarak baslat.

### 4. Firewall

```bash
sudo ufw allow 5601    # Kibana
sudo ufw allow 9200    # Elasticsearch API
sudo ufw allow 5044    # Logstash Beats input
sudo ufw allow 22      # SSH
```

---

## Proje Yapisi

```
ExchangeELK/
|-- docker-compose.yml                       Container orkestrasyon (bind mount -> /data)
|-- .env                                     JVM heap, port, yol degiskenleri
|-- elasticsearch/
|   +-- config/elasticsearch.yml            Cluster, path.data, security ayarlari
|-- logstash/
|   |-- config/
|   |   |-- logstash.yml                   Persistent Queue (4 GB) + DLQ (1 GB)
|   |   +-- pipelines.yml                  5 pipeline tanimi (pipeline-to-pipeline)
|   |-- geoip/
|   |   +-- GeoLite2-City.mmdb             MaxMind GeoIP (deploy sonrasi yukle, .gitignore)
|   +-- pipeline/
|       |-- pipeline-router.conf           Giris noktasi - port 5044, tag bazli yonlendirme
|       |-- pipeline-message-tracking.conf MessageTracking CSV (30 sutun)
|       |-- pipeline-iis.conf              IIS W3C + X-Forwarded-For + GeoIP
|       |-- pipeline-http-protocol.conf    HttpProxy (77 alan) + MapiHttp (47 alan)
|       +-- pipeline-smtp.conf             SMTP Receive + Send protokol loglari
|-- kibana/config/kibana.yml
|-- filebeat/config/filebeat.yml            Exchange sunuculara deploy edilen konfig
|-- scripts/
|   |-- deploy.sh                           Ana deployment scripti
|   |-- setup-disk.sh                       2. disk partition ve /data mount
|   |-- setup-ilm.sh                        ILM policy + component template + SLM
|   |-- setup-exchange-forwarding.ps1       Exchange sunucu Filebeat kurulumu
|   +-- health-check.sh                     Servis saglik kontrolu
+-- dashboards/
    |-- exchange-main-dashboard.ndjson      Ana dashboard (18 panel)
    |-- exchange-msgtrak-dashboard.ndjson   Message Tracking detay dashboard (16 obje)
    +-- exchange-search-dashboard.ndjson    Mesaj arama dashboard (7 obje)
```

---

## Log Turleri ve Index Yapisi

| Filebeat Tag | Log Konumu (Exchange) | Elasticsearch Index | Pipeline |
|---|---|---|---|
| `ExchangeMsgTrack` | `%ExchangePath%\Logging\MessageTracking\*.log` | `exchange-msgtrk-YYYY.MM.dd` | pipeline-message-tracking |
| `ExchangeIIS` | `C:\inetpub\logs\LogFiles\W3SVC*\*.log` | `exchange-iis-YYYY.MM.dd` | pipeline-iis |
| `HttpProxy` | `%ExchangePath%\Logging\HttpProxy\*\*.log` | `exchange-httpproxy-YYYY.MM.dd` | pipeline-http-protocol |
| `MapiHttp` | `%ExchangePath%\Logging\MapiHttp\Emsmdb\*.log` | `exchange-mapihttp-YYYY.MM.dd` | pipeline-http-protocol |
| `SmtpReceive` | `%ExchangePath%\Logging\ProtocolLog\SmtpReceive\*.log` | `exchange-smtp-receive-YYYY.MM.dd` | pipeline-smtp |
| `SmtpSend` | `%ExchangePath%\Logging\ProtocolLog\SmtpSend\*.log` | `exchange-smtp-send-YYYY.MM.dd` | pipeline-smtp |

**ILM (Index Lifecycle Management):**
- Hot (0-7 gun): LZ4, 3 primary shard, aktif yazma
- Warm (7-30 gun): best_compression, forcemerge 1 segment, read-only
- Cold (30-90 gun): freeze (dusuk bellek), best_compression
- Delete (90 gun): kalici silme

---

## Kibana Dashboard'lari

### Exchange Server - Ana Dashboard (`exchange-main-dashboard.ndjson`)
18 panel. 7 gunluk gorunum, 5 dakika otomatik yenile.

| Panel | Kaynak | Aciklama |
|---|---|---|
| MessageTracking Events Over Time | msgtrk | Saatlik event dagilimi |
| Gelen E-posta Hacmi | msgtrk | RECEIVE event toplam byte |
| Giden Mesaj Sayisi | msgtrk | SEND + SENDEXTERNAL event sayisi |
| Teslim Edilen Mesajlar | msgtrk | DELIVER event sayisi |
| Top 10 Gonderici | msgtrk | En cok mail gonderen adresler (tablo) |
| Top 10 Alici | msgtrk | En cok mail alan adresler (tablo) |
| Event ID Dagilimi | msgtrk | Pie chart |
| IIS Saatlik HTTP Istek Hacmi | iis | Sunucu bazli |
| IIS Top 10 Istemci IP | iis | Horizontal bar |
| SMTP Send Gunluk Hacim | smtp-send | Bar chart |
| Exchange Server Dagilimi | iis | Donut chart |
| Gonderici Domain Dagilimi | msgtrk | Pie chart |
| Gunluk Mesaj Trafigi (Gelen/Giden) | msgtrk | Grouped bar |
| IIS Istemci IP Haritasi | iis | Tile map (GeoIP gerektirir) |

### Exchange Message Tracking Logs (`exchange-msgtrak-dashboard.ndjson`)
16 obje. Detayli mesaj akis analizi.

- Inbound/Outbound rate ve hacim grafikleri
- Saved searches: Received Emails, Sent Emails, All Events
- Top 10 Gonderici/Alici tablolari
- Sutunlar: zaman, gonderen, alici, konu, event-id, event-id-tr, mesaj boyutu

### Exchange - Mesaj Arama (`exchange-search-dashboard.ndjson`)
7 obje. Helpdesk kullanimi icin.

- Filtre bari: Gonderen, Alici, Konu, Message ID dropdown secimi
- Metrik satiri: Toplam Kayit, Basarili Iletim (DELIVER+SENDEXTERNAL), Hata (DROP/FAIL/BADMAIL), Benzersiz Gonderici
- Sonuc tablosu: timestamp, gonderen, alici, konu, event-id, event-id-tr, mesaj boyutu, kaynak

**event-id Turkce karsiliklari** (scripted field `event-id-tr`):

| event-id | Anlam |
|---|---|
| RECEIVE | Alindi (gelen) |
| DELIVER | Ic Teslim OK |
| SEND | Gonderildi |
| SENDEXTERNAL | Dis Gonderim OK |
| TRANSFER | Aktarildi |
| DROP | Dusuruldu! |
| FAIL | HATA! |
| DSN | Teslimat Raporu |

---

## Yonetim

### Servis Durumu

```bash
docker compose ps
docker compose logs logstash --tail=50
curl -s http://localhost:9200/_cluster/health?pretty
curl -s http://localhost:9600/_node/stats/pipelines | python3 -m json.tool
```

### Dashboard Import (guncelleme sonrasi)

```bash
cd /opt/exchange-elk
git pull
for f in dashboards/*.ndjson; do
  curl -X POST "http://localhost:5601/api/saved_objects/_import?overwrite=true" \
    -H "kbn-xsrf: true" -F file=@"$f"
done
```

### ILM Durumu

```bash
curl -s "http://localhost:9200/_ilm/policy/exchange-logs-policy?pretty"
curl -s "http://localhost:9200/_cat/indices?v&s=index:desc&h=index,docs.count,store.size,status"
```

### Snapshot / Backup

Otomatik snapshot: her gece 02:30 -- `/data/elasticsearch/backups`

```bash
# Manuel snapshot
curl -X PUT "http://localhost:9200/_slm/policy/exchange-daily-snapshot/_execute"

# Snapshot listesi
curl "http://localhost:9200/_snapshot/exchange-backups/_all?pretty"
```

---

## Sorun Giderme

### Logstash pipeline hatasi

```bash
docker exec logstash logstash --config.test_and_exit \
  -f /usr/share/logstash/pipeline/pipeline-router.conf
```

### Index mapping hatasi (fielddata disabled)

Text alan aggregation gerektiriyorsa `.keyword` alt alani kullanilmali:
```bash
curl -X PUT "http://localhost:9200/exchange-msgtrk-*/_mapping" \
  -H "Content-Type: application/json" \
  -d '{"properties":{"message-subject":{"type":"text","fields":{"keyword":{"type":"keyword","ignore_above":512}}}}}'
```

### GeoIP harita bos

1. `logstash/geoip/GeoLite2-City.mmdb` dosyasinin var oldugunu dogrula
2. `docker compose restart logstash`
3. Yeni gelen loglar icin geoip.location alanini kontrol et:
```bash
curl -s "http://localhost:9200/exchange-iis-*/_search" \
  -d '{"query":{"exists":{"field":"geoip.location"}},"size":1}' \
  -H "Content-Type: application/json"
```

### Filebeat baglanti sorunu

```powershell
Test-NetConnection -ComputerName 10.11.12.19 -Port 5044
Restart-Service filebeat
```

---

## Guvenlik Notu

Bu kurulumda `xpack.security.enabled: false` ile deploy edilmistir (ic ag, pilot).
Production ortaminda TLS ve kimlik dogrulama aktif edilmelidir.
