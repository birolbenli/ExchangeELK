# Exchange Server ELK Stack - Mimari Dokumantasyon

ELK 8.11.1 -- Docker Compose -- Ubuntu 22.04 LTS

---

## Genel Yapi

```
Exchange Servers (Windows) - DAG ortami, 600 mailbox
    |-- Message Tracking Logs   (tag: MessageTracking)
    |-- IIS W3C Logs            (tag: ExchangeIIS)
    |-- HttpProxy Protocol Logs (tag: HttpProxy)
    |-- MapiHttp Protocol Logs  (tag: MapiHttp)
    |-- SMTP Receive Logs       (tag: SmtpReceive)
    |-- SMTP Send Logs          (tag: SmtpSend)
              |
              v  Filebeat Agent (Windows, port 5044)
              |
FortiMail Cihazi
    |-- History Logs  (posta trafik)
    |-- Spam Logs
    |-- Virus Logs
    |-- Event Logs
              |
              v  Syslog UDP/TCP (port 5514, dogrudan Logstash'e)
              |
    +--------------------------------------------------+
    |  Ubuntu ELK Server  10.11.12.19                  |
    |  Sistem: 100 GB SSD (OS + Docker images)         |
    |  Veri:   2 TB SSD  -> /data                      |
    |                                                   |
    |  +--------------------+  +--------------------+  |
    |  |   Logstash :5044   |  |   Logstash :5514   |  |
    |  |   5 Pipeline (P2P) |  |   FortiMail Syslog |  |
    |  |   Exchange Logs    |  |   UDP + TCP        |  |
    |  +-------+------------+  +-------+------------+  |
    |          |                        |               |
    |          v (pipeline-to-pipeline) v               |
    |  +----------------------------------------------+ |
    |  |          Elasticsearch:9200                   | |
    |  |  exchange-msgtrk-*  exchange-iis-*            | |
    |  |  exchange-smtp-*    fortimail-history-*        | |
    |  |  fortimail-spam-*   fortimail-virus-*          | |
    |  |  ILM: hot->warm->cold->delete                 | |
    |  +----------------------------------------------+ |
    |          |                                        |
    |  +-------+------------+                          |
    |  |   Kibana :5601     | 4 dashboard              |
    |  |  Exchange + FortiMail dashboards              |
    |  +--------------------+                          |
    +--------------------------------------------------+
```

---

## Logstash Pipeline Mimarisi (Pipeline-to-Pipeline)

### Veri Akis Sekli

```
Filebeat
  |
  v  port 5044
pipeline-router
  |-- tag: MessageTracking (alias: ExchangeMsgTrack)  --> pipeline-message-tracking
  |-- tag: ExchangeIIS       --> pipeline-iis
  |-- tag: HttpProxy         --> pipeline-http-protocol
  |-- tag: MapiHttp          --> pipeline-http-protocol
  |-- tag: SmtpReceive       --> pipeline-smtp
  |-- tag: SmtpSend          --> pipeline-smtp
```

### Pipeline Detaylari

| Dosya | Giris | Cikis | Aciklama |
|---|---|---|---|
| `pipeline-router.conf` | beats port 5044 | pipeline output | Tag'e gore yonlendirme |
| `pipeline-message-tracking.conf` | pipeline input | `exchange-msgtrk-*` | CSV parse, 30 sutun, GeoIP |
| `pipeline-iis.conf` | pipeline input | `exchange-iis-*` | W3C parse, X-Forwarded-For, GeoIP |
| `pipeline-http-protocol.conf` | pipeline input | `exchange-httpproxy-*` / `exchange-mapihttp-*` | HttpProxy: 77 alan, MapiHttp: 47 alan |
| `pipeline-smtp.conf` | pipeline input | `exchange-smtp-receive-*` / `exchange-smtp-send-*` | SMTP protokol loglari |

### Performans Ayarlari (`logstash.yml`)

```yaml
pipeline.workers: 4
pipeline.batch.size: 500
pipeline.batch.delay: 50
queue.type: persisted
queue.max_bytes: 4gb
dead_letter_queue.enable: true
dead_letter_queue.max_bytes: 1gb
```

---

## Elasticsearch Index Yapisi

### Index Gruplari

| Index Pattern | Kaynak | Gunluk Boyut |
|---|---|---|
| `exchange-msgtrk-YYYY.MM.dd` | Message Tracking | ~500 MB |
| `exchange-iis-YYYY.MM.dd` | IIS W3C | ~250 MB |
| `exchange-httpproxy-YYYY.MM.dd` | HttpProxy | ~200 MB |
| `exchange-mapihttp-YYYY.MM.dd` | MapiHttp | ~100 MB |
| `exchange-smtp-receive-YYYY.MM.dd` | SMTP Receive | ~80 MB |
| `exchange-smtp-send-YYYY.MM.dd` | SMTP Send | ~50 MB |

### Index Template (Component Template Bazli)

`setup-ilm.sh` tarafindan olusturulur:

1. **`exchange-component-settings`**: ILM policy baglantisi, shard/replica sayisi
2. **`exchange-component-mappings`**: Alan tipleri
   - `@timestamp`: date
   - `geoip.location`: geo_point (harita icin)
   - `total-bytes`, `message-size`: long
   - `message-subject`: text + `.keyword` alt-alani
   - `sender-address`, `recipient-address`: keyword
3. **`exchange-index-template`**: Yukaridaki 2 component'i `exchange-*` pattern'ine baglar

### ILM Policy (`exchange-logs-policy`)

```
Hot   (0-7 gun)  : LZ4, max_primary_shard_size 50GB, 3 primary shard
                   rollover: max_age 1d VEYA max_size 50GB
Warm  (7-30 gun) : best_compression, forcemerge (1 segment), shrink, read-only
Cold  (30-90 gun): freeze, best_compression
Delete (90 gun)  : kalici silme
```

### Snapshot Policy (SLM)

- Policy adi: `exchange-daily-snapshot`
- Zamanlama: Her gece 02:30 (`0 30 2 * * ?`)
- Kapsam: `exchange-*` index'leri
- Sakla: son 7 snapshot
- Konum: `/data/elasticsearch/backups`

---

## GeoIP Zenginlestirme

### Gereksinim

MaxMind GeoLite2-City.mmdb dosyasi `logstash/geoip/` altinda olmali.
Docker volume olarak mount edilir: `./logstash/geoip:/usr/share/logstash/geoip:ro`

### GeoIP Kullanan Pipeline'lar

- `pipeline-iis.conf`: `client_ip` alani -> `geoip.location`
- `pipeline-message-tracking.conf`: `client-ip` alani -> `geoip.location`

### Kritik Ayar

Tum geoip filter bloklari icin ecs_compatibility kapanmali:
```
geoip {
    source => "client_ip"
    target => "geoip"
    database => "/usr/share/logstash/geoip/GeoLite2-City.mmdb"
    ecs_compatibility => "disabled"
}
```

---

## Kibana Yapisi

### Index Pattern'lar

| Pattern | Pipeline | Zaman Alani |
|---|---|---|
| `exchange-msgtrk-ip` | message-tracking | `@timestamp` |
| `exchange-iis-*` | iis | `@timestamp` |
| `exchange-httpproxy-*` | http-protocol | `@timestamp` |
| `exchange-mapihttp-*` | http-protocol | `@timestamp` |
| `exchange-smtp-receive-*` | smtp | `@timestamp` |
| `exchange-smtp-send-*` | smtp | `@timestamp` |

`ex-msgtrk-ip` pattern'inde ek scripted field:

```
Ad  : event-id-tr
Dil : Painless
Kod : doc['event-id.keyword'] varsa Turkce karsilik, yoksa orijinal deger
```

### Dashboard'lar

#### exchange-main-dashboard.ndjson (18 obje)
- 3 index-pattern referansi (msgtrk, iis, smtp-send)
- Metrik panel'lar: Gelen Hacim, Giden Sayi, Teslim Edilen
- Tablo panel'lar: Top 10 Gonderici, Top 10 Alici (data table, keyword aggregation)
- Harita: Tile map, `geoip.location`, match_all query
- Grafik: Saatlik events, gunluk grouped bar, donut

#### exchange-msgtrak-dashboard.ndjson (16 obje)
- Yalnizca `exchange-msgtrk-ip` kaynagi
- Inbound/Outbound rate + hacim
- Saved searches: Received, Sent, All Events
- Top 10 Gonderici/Alici (tablo)

#### exchange-search-dashboard.ndjson (7 obje)
- Input control: 4 filtre (sender, recipient, subject, message-id)
- Metrik: Toplam Kayit, Basarili (DELIVER+SENDEXTERNAL), Hata (DROP+FAIL+BADMAIL), Benzersiz Gonderici
- Saved search: 9 sutunlu sonuc tablosu (event-id-tr dahil)

---

## Donanim ve Kapasite

### Sunucu Konfigurasyonu

| Bilesen | Deger |
|---|---|
| Hostname | eqlpexcelk01 |
| IP | 10.11.12.19 |
| OS | Ubuntu 22.04 LTS |
| RAM | 32 GB |
| CPU | 8 Core |
| Sistem Diski | 100 GB SSD |
| Veri Diski | 2 TB SSD (/data) |

### JVM Heap Boyutlari

| Servis | Min | Max |
|---|---|---|
| Elasticsearch | 8 GB | 16 GB |
| Logstash | 2 GB | 4 GB |

### Filebeat Kaynaklar (Exchange)

| Sunucu | Rol | Filebeat Versiyon |
|---|---|---|
| EQWPLBREXC01 | Exchange DAG Node | 8.11.1 |
| (diger DAG node'lari) | Exchange DAG Node | 8.11.1 |

---

## Guvenlik Mimari

Mevcut durum (pilot/ic ag):
- `xpack.security.enabled: false`
- Logstash <-> Elasticsearch: TLS yok
- Filebeat <-> Logstash: TLS yok
- Kibana: kimlik dogrulama yok

Production icin onerilen degisiklikler:
- Elasticsearch TLS + enrollment token ile secure cluster
- Logstash beats input: ssl certificate
- Kibana: x-pack security ile kullanici/rol yonetimi
- Network: Filebeat portu (5044) firewall ile yalnizca Exchange sunuculardan erisilebilir

---

## Sorun Giderme ve Izleme

### Saglik Kontrol Script'i

```bash
./scripts/health-check.sh
```

Kontrol eder: Docker container durumu, Elasticsearch cluster health, Logstash pipeline metrikleri, toplam dokuman sayilari, disk kullanimi.

### Log Konumlari (Docker)

```bash
docker compose logs elasticsearch --tail=100
docker compose logs logstash --tail=100
docker compose logs kibana --tail=100
```

### Pipeline Metrikleri

```bash
curl -s "http://localhost:9600/_node/stats/pipelines" | python3 -m json.tool
```

Her pipeline icin: events.in, events.out, events.filtered, events.duration_in_millis