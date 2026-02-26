# Exchange Server DAG ELK Stack Project

600 mailbox kapasiteli Exchange Server DAG ortamı için kapsamlı log toplama, işleme ve görselleştirme sistemi.

## 📋 Proje Özellikleri

- **Exchange Server Log Toplama**: Message tracking, IIS, SMTP, Transport logları
- **Real-time Processing**: Logstash ile gerçek zamanlı log işleme
- **Görselleştirme**: Kibana dashboard'ları ile detaylı analiz
- **Arama Yetenekleri**: Kim kime mail attı, hangi IP'den erişim vs.
- **Scalable Architecture**: 600+ mailbox için optimize edilmiş
- **Docker-based Deployment**: Kolay kurulum ve yönetim

## 🖥️ Sistem Gereksinimleri

### Ubuntu Sunucu Gereksinimleri (600 Mailbox, 90 Gün Retention)

| Özellik | Minimum | **Önerilen** |
|---------|---------|-------------|
| **RAM** | 24 GB | **32 GB** |
| **CPU** | 6 Core | **8 Core** |
| **Sistem Diski** | 60 GB SSD | **100 GB SSD** (sadece OS + Docker) |
| **Data Diski** | 1 TB SSD | **2 TB SSD/NVMe** (tüm ES verisi) |
| **Network** | 1 Gbps | **1 Gbps** |
| **OS** | Ubuntu 22.04 LTS | **Ubuntu 22.04 LTS** |

> ⚠️ **Kritik**: Elasticsearch, Logstash ve tüm log verileri **sistem diskine değil** 2. diske (`/data`) yazılır.  
> Sistem diski yalnızca Ubuntu + Docker kurulumu için kullanılır (~15–20 GB).

### Disk Kullanımı Projeksiyonu (600 Mailbox, 90 Gün)

```
Günlük Ham Log Üretimi (~600 mailbox, ortalama trafik):
  Message Tracking : ~2 GB/gün
  IIS Logs         : ~1 GB/gün
  SMTP Logs        : ~500 MB/gün
  Transport Logs   : ~500 MB/gün
  Toplam ham       : ~4 GB/gün

90 günlük ham veri: ~360 GB

ILM + Elasticsearch sıkıştırma sonrası kullanım:
  Hot  (0-7g)   : ~28 GB   — LZ4, 3 shard, aktif yazma
  Warm (7-30g)  : ~46 GB   — best_compression + forcemerge → 1 segment/shard
  Cold (30-90g) : ~72 GB   — freeze (bellek tasoarrufu), best_compression
  Toplam ES     : ~146 GB

Filebeat registry + Logstash queue : ~5 GB
Snapshot yedekler (30 gün)         : ~60 GB
Toplam /data kullanımı             : ~211 GB

2 TB disk → %10 kullanım → Güvenli büyüme payı ile idealdir.
```

## 🚀 Kurulum

### 1. Ubuntu Sunucuya Deployment

```bash
# Repository'yi klonlayın
git clone https://github.com/birolbenli/ExchangeELK.git
cd ExchangeELK
chmod +x scripts/*.sh

# (İsteğe bağlı) Önce 2. diski manuel kurun (deploy.sh de otomatik yapar)
# /dev/sdb → /data mount eder, Docker data-root'u /data/docker'a taşır
sudo ./scripts/setup-disk.sh /dev/sdb

# Ana deployment (Docker kurulumu + disk ayarı + ILM + Kibana)
# Argüman 1: GitHub repo URL'si, Argüman 2: data disk (/dev/sdb varsayılan)
sudo ./scripts/deploy.sh https://github.com/birolbenli/ExchangeELK.git /dev/sdb

# ILM policy'yi yeniden uygulamak istersen (idempotent)
sudo ./scripts/setup-ilm.sh
```

### 2. Exchange Server'larda Log Forwarding Kurulumu

Her Exchange Server'da PowerShell ile:

```powershell
# ELK sunucu IP'si ile script'i çalıştırın
.\scripts\setup-exchange-forwarding.ps1 -ELKServerIP "192.168.1.100" -InstallFilebeatAgent
```

### 3. Firewall Kuralları

Ubuntu sunucuda gerekli portları açın:

```bash
sudo ufw allow 5601    # Kibana
sudo ufw allow 9200    # Elasticsearch API
sudo ufw allow 5044    # Logstash Beats input
sudo ufw allow 22      # SSH
```

## 📁 Proje Yapısı

```
ExchangeELK/
├── docker-compose.yml           # Ana container orchestration (bind mounts → /data)
├── .env                        # Environment variables (heap, disk yolları)
├── elasticsearch/
│   ├── config/
│   │   └── elasticsearch.yml   # ES konfigürasyonu (path.data → /data)
│   └── ilm-policy.json         # ILM referans (setup-ilm.sh uygular)
├── logstash/
│   ├── config/
│   │   ├── logstash.yml         # Persistent Queue (4 GB) + DLQ (1 GB)
│   │   └── pipelines.yml        # 5 pipeline tanımı (P2P mimarisi)
│   ├── pipeline/
│   │   ├── pipeline-router.conf             # Giriş noktası (port 5044)
│   │   ├── pipeline-message-tracking.conf   # MessageTracking CSV (30 sütun)
│   │   ├── pipeline-iis.conf                # IIS W3C + X-Forwarded-For
│   │   ├── pipeline-http-protocol.conf      # HttpProxy (77) + MapiHttp (47)
│   │   ├── pipeline-smtp.conf               # SMTP Receive + Send
│   │   └── exchange-logs.conf               # [ARŞİV] kullanılmıyor
│   └── templates/
│       └── exchange-template.json
├── kibana/
│   └── config/
│       └── kibana.yml
├── filebeat/
│   ├── config/
│   │   └── filebeat.yml
│   └── modules.d/
├── scripts/
│   ├── deploy.sh                      # Ana deployment
│   ├── setup-disk.sh                  # 2. disk partition + /data mount
│   ├── setup-ilm.sh                   # ILM policy + template + SLM
│   ├── setup-exchange-forwarding.ps1  # Exchange sunucu ayarları
│   └── health-check.sh
├── dashboards/
│   └── exchange-overview-dashboard.json
└── docs/
    └── ARCHITECTURE.md
```

## 🔧 Konfigürasyon

### Exchange Log Türleri

| Log Türü | Dosya Konumu | Açıklama |
|-----------|--------------|----------|
| **Message Tracking** | `%ExchangePath%\Logging\MessageTracking\*.log` | E-posta takip logları (30 alan CSV) |
| **IIS W3C** | `C:\inetpub\logs\LogFiles\W3SVC*\*.log` | Web erişim logları (X-Forwarded-For aktif) |
| **HttpProxy** | `%ExchangePath%\Logging\HttpProxy\*\*.log` | HTTP proxy protokol logları (77 alan) |
| **MapiHttp** | `%ExchangePath%\Logging\MapiHttp\Emsmdb\*.log` | MAPI over HTTP logları (47 alan) |
| **SMTP Receive** | `%ExchangePath%\Logging\ProtocolLog\SmtpReceive\*.log` | Gelen SMTP protokol logları |
| **SMTP Send** | `%ExchangePath%\Logging\ProtocolLog\SmtpSend\*.log` | Giden SMTP protokol logları |

### Elasticsearch Index Settings

```
Index Patterns (günlük oluşturulur, YYYY.MM.dd suffix):
  exchange-msgtrk-*         : Message Tracking logs
  exchange-iis-*            : IIS W3C logs
  exchange-httpproxy-*      : HttpProxy protocol logs
  exchange-mapihttp-*       : MapiHttp protocol logs
  exchange-smtp-receive-*   : SMTP Receive logs
  exchange-smtp-send-*      : SMTP Send logs

Shards: 3  |  Replicas: 0  |  Refresh: 30s
Retention: 90 gün (ILM: Hot 7g → Warm 30g → Cold 90g → Delete)
Sıkıştırma: Hot=LZ4, Warm/Cold=best_compression + forcemerge
```

## 📊 Dashboard'lar

### Ana Dashboard'lar

1. **Exchange Overview**: Genel sistem durumu ve istatistikler
2. **Message Flow Analysis**: E-posta akış analizi
3. **Security Dashboard**: Güvenlik olayları ve anomaliler
4. **Performance Monitoring**: Performans metrikleri
5. **User Activity**: Kullanıcı aktivite raporları

### Önemli Metrikler

- **Hourly Message Volume**: Saatlik e-posta hacmi
- **Top Senders/Recipients**: En aktif gönderen/alan kullanıcılar
- **Failed Delivery Analysis**: Başarısız teslimat analizi
- **External/Internal Mail Ratio**: Dış/iç mail oranı
- **Server Performance**: Sunucu performans metrikleri

## 🔍 Arama Örnekleri

### Kibana Discovery'de Kullanışlı Sorgular

```lucene
# Belirli bir kullanıcının gönderdiği mailler (exchange-msgtrk-* index)
sender-address: "kullanici@firma.com"

# Son 1 saatte başarısız teslimatlar
recipient-status: "Failed" AND @timestamp: [now-1h TO now]

# Belirli bir domain'e gönderilen mailler
recipient_domain: "gmail.com"

# Büyük boyutlu mailler (>10MB)
total-bytes: >10485760

# Dış domain'lerden gelen mailler
NOT sender_domain: "firma.com" AND directionality: "Incoming"

# Belirli bir IP'den gelen IIS istekleri (exchange-iis-* index)
clientIP: "1.2.3.4" OR OrgclientIP: "1.2.3.4"

# SMTP bağlantı hataları (exchange-smtp-receive-* index)
event-id: *fail* OR event-id: *reject*

# HttpProxy hatalı yanıtlar (exchange-httpproxy-* index)
HttpStatus: >499
```

## 🛠️ Yönetim ve Bakım

### Günlük İşlemler

```bash
# Servis durumunu kontrol et
docker-compose ps

# Logları kontrol et
docker-compose logs elasticsearch
docker-compose logs logstash
docker-compose logs kibana

# Elasticsearch cluster sağlığı
curl -X GET "localhost:9200/_cluster/health?pretty"

# Index durumu
curl -X GET "localhost:9200/_cat/indices?v"
```

### Performans Optimizasyonu

```bash
# Elasticsearch heap boyutunu ayarla (.env dosyasında)
ES_JAVA_OPTS=-Xms16g -Xmx16g

# Logstash pipeline worker sayılarını artır (logstash/config/pipelines.yml'de)
pipeline.workers: 4   # exchange-router için

# ILM policy durumunu kontrol et
curl -X GET "localhost:9200/_ilm/policy/exchange-logs-policy?pretty"

# Tüm pipeline durumlarını listele
curl "localhost:9600/_node/stats/pipelines?pretty"
```

### Backup ve Recovery

```bash
# Snapshot repository zaten kurulu (setup-ilm.sh ile oluşturuldu)
# SLM: Her gece 02:30'da otomatik snapshot alınır → /data/elasticsearch/backups

# Manuel snapshot al
curl -X PUT "localhost:9200/_slm/policy/exchange-daily-snapshot/_execute"

# Mevcut snapshotları listele
curl "localhost:9200/_snapshot/exchange-backups/_all?pretty"

# Son snapshot durumunu kontrol et
curl "localhost:9200/_slm/policy/exchange-daily-snapshot?pretty"
```

## 🚨 Monitoring ve Alerting

### Sistem Metrikleri

- **Elasticsearch**: Cluster health, index size, search performance
- **Logstash**: Processing rate, pipeline errors, memory usage
- **Filebeat**: Harvester status, log shipping delays
- **System**: CPU, Memory, Disk I/O, Network

### Alert Kuralları (Önerilir)

1. **Elasticsearch disk usage > 85%**
2. **Logstash processing lag > 5 minutes**
3. **Filebeat connection errors**
4. **Unusual email volume spikes**
5. **Authentication failures**

## 🔐 Güvenlik

### Exchange Server'da

```powershell
# Filebeat service account oluştur
New-LocalUser -Name "FilebeatService" -Description "Filebeat Log Collection"
Add-LocalGroupMember -Group "Event Log Readers" -Member "FilebeatService"
```

### Ubuntu Server'da

```bash
# Elasticsearch güvenliği (production için)
# elasticsearch.yml'de:
xpack.security.enabled: true
xpack.security.http.ssl.enabled: true

# Kibana authentication
# kibana.yml'de:
xpack.security.enabled: true
elasticsearch.username: "kibana_system"
```

## 🐛 Troubleshooting

### Yaygın Problemler

#### Elasticsearch başlamıyor
```bash
# Memory lock kontrolü
grep "memory lock" /var/log/elasticsearch/elasticsearch.log

# vm.max_map_count ayarı
sudo sysctl -w vm.max_map_count=262144
```

#### Logstash pipeline hataları
```bash
# Tüm pipeline config'lerini test et
docker exec logstash logstash --config.test_and_exit -f /usr/share/logstash/pipeline/pipeline-router.conf

# Logstash pipeline durumlarını kontrol et
curl localhost:9600/_node/stats/pipelines?pretty | jq .pipelines

# Dead Letter Queue içeriğini incele
docker exec logstash ls /usr/share/logstash/data/dead_letter_queue/
```

#### Filebeat bağlantı sorunları
```bash
# Exchange server'dan ELK server bağlantısı test
Test-NetConnection -ComputerName ELK_SERVER_IP -Port 5044
```

## 📞 Destek ve Katkı

- **Issues**: GitHub Issues bölümünden sorun bildirebilirsiniz
- **Wiki**: Detaylı dokümantasyon için Wiki sayfalarını kontrol edin
- **Discussions**: Topluluk desteği için GitHub Discussions kullanın

## 📝 License

Bu proje MIT lisansı ile lisanslanmıştır. Detaylar için `LICENSE` dosyasına bakın.

## 🔄 Versiyon Geçmişi

- **v1.0.0**: Temel ELK stack kurulumu
- **v1.1.0**: Exchange-specific CSV parser'lar (MessageTracking 30 sütun)
- **v1.2.0**: Pipeline-to-Pipeline mimarisine geçiş (5 bağımsız pipeline)
- **v1.3.0**: IIS X-Forwarded-For (OrgclientIP), GeoIP, Europe/Istanbul timezone
- **v1.4.0**: Tüm veriler 2. diske (/data); ILM Hot→Warm→Cold→Delete; PQ+DLQ

---

**Not**: Bu sistem production ortamda kullanılmadan önce test ortamında detaylı testlerden geçirilmelidir. Güvenlik ayarları production gereksinimlerinize göre düzenlenmelidir.