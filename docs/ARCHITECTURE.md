# Exchange Server ELK Stack Architecture

## Sistem Mimarisi

```
Exchange Servers (Windows) — DAG ortamı, 600 mailbox
    ├─ Message Tracking Logs   (tag: MessageTracking)
    ├─ IIS W3C Logs            (tag: ExchangeIIS)
    ├─ HttpProxy Protocol Logs (tag: HttpProxy)
    ├─ MapiHttp Protocol Logs  (tag: MapiHttp)
    ├─ SMTP Receive Logs       (tag: SmtpReceive)
    └─ SMTP Send Logs          (tag: SmtpSend)
              │
              ▼  Filebeat Agent (Windows, port 5044)
              │
    ┌────────────────────────────────────────────────┐
    │   Ubuntu ELK Server (32GB RAM / 8 CPU)          │
    │   Sistem diski: 100 GB (OS+Docker only)         │
    │   Veri diski:   2 TB  → /data                  │
    │                                                  │
    │  ┌──────────────────────────────────────────┐  │
    │  │  Logstash — Pipeline-to-Pipeline (P2P)   │  │
    │  │                                          │  │
    │  │  [pipeline-router]       ← port 5044    │  │
    │  │      │ tag=MessageTracking               │  │
    │  │      ├──► [pipeline-message-tracking]    │  │
    │  │      │ tag=ExchangeIIS                   │  │
    │  │      ├──► [pipeline-iis]                 │  │
    │  │      │ tag=HttpProxy / MapiHttp           │  │
    │  │      ├──► [pipeline-http-protocol]        │  │
    │  │      │ tag=SmtpReceive / SmtpSend         │  │
    │  │      └──► [pipeline-smtp]                │  │
    │  └───────────────────┬──────────────────────┘  │
    │                      │                          │
    │  ┌───────────────────▼──────────────────────┐  │
    │  │        Elasticsearch  (port 9200)         │  │
    │  │   JVM Heap: 16 GB  │  /data/elasticsearch │  │
    │  └───────────────────┬──────────────────────┘  │
    │                      │                          │
    │  ┌───────────────────▼──────────────────────┐  │
    │  │          Kibana  (port 5601)              │  │
    │  └──────────────────────────────────────────┘  │
    └────────────────────────────────────────────────┘
```

## Veri Akışı

### 1. Log Toplama — Windows Exchange → Filebeat

Filebeat, Windows Exchange sunucularında çalışır ve 6 farklı log tipini takip eder:

| Tag              | Kaynak Yol                                    | Hedef Index              |
|------------------|-----------------------------------------------|--------------------------|
| MessageTracking  | `V15\TransportRoles\Logs\MessageTracking\*.log`| exchange-msgtrk-*        |
| ExchangeIIS      | `W3SVC\W3SVC*\u_ex*.log`                      | exchange-iis-*           |
| HttpProxy        | `V15\Logging\HttpProxy\*.log`                 | exchange-httpproxy-*     |
| MapiHttp         | `V15\Logging\MapiHttp\*.log`                  | exchange-mapihttp-*      |
| SmtpReceive      | `V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SmtpReceive\*.log` | exchange-smtp-receive-* |
| SmtpSend         | `V15\TransportRoles\Logs\FrontEnd\ProtocolLog\SmtpSend\*.log`    | exchange-smtp-send-*    |

Tüm Filebeat çıktısı tek bir porta yönlendirilir: `logstash:5044`

### 2. Log İşleme — Logstash Pipeline-to-Pipeline Mimarisi

```
Filebeat (port 5044)
       │
       ▼
[exchange-router pipeline]
  ├── # ile başlayan satırları DROP et
  ├── tag=MessageTracking  → pipeline://exchange-message-tracking
  ├── tag=ExchangeIIS      → pipeline://exchange-iis
  ├── tag=HttpProxy        –┐
  ├── tag=MapiHttp          ├→ pipeline://exchange-http-protocol
  ├── tag=SmtpReceive      –┐
  └── tag=SmtpSend          ├→ pipeline://exchange-smtp
```

Her downstream pipeline'ın uyguladığı işlemler:

- **pipeline-message-tracking.conf**: CSV parse (30 sütun), GeoIP `original-client-ip` üzerinde, recipient-address/source-context multi-value split (`;`), sender/recipient domain extraction, Europe/Istanbul timezone
- **pipeline-iis.conf**: Grok W3C parse, X-Forwarded-For → `OrgclientIP`, GeoIP önce OrgclientIP sonra clientIP (fallback), useragent parse, Europe/Istanbul timezone
- **pipeline-http-protocol.conf**: HttpProxy CSV (77 sütun) ve MapiHttp CSV (47 sütun), MapiHttp cookie/session alanları temizleme, GeoIP, Europe/Istanbul timezone
- **pipeline-smtp.conf**: CSV 9 sütun, remote-endpoint → remote-ip + remote-port split, GeoIP, Europe/Istanbul timezone

**GeoIP Özel Filtre** (tüm pipeline'larda ortak):
```ruby
# Sadece harici IP'lere GeoIP uygulanır, RFC1918 + loopback atlanır
if [ip_field] !~ /(^127\.)|(^10\.)|(^172\.1[6-9]\.)|(^172\.2[0-9]\.)|(^172\.3[0-1]\.)|(^192\.168\.)|(^169\.254\.)|(\:\:1)|(^-$)|(^$)/ {
  geoip { ... }
}
```

**Logstash Dayanıklılık:**
- **Persistent Queue**: 4 GB — yeniden başlatmada event kaybı olmaz
- **Dead Letter Queue**: 1 GB — parse edilemeyen event'lar DLQ'ya yönlendirilir
- `config.reload.automatic: true` — pipeline değişiklikleri restart gerektirmez

### 3. Veri Saklama — Elasticsearch ILM (Index Lifecycle Management)

```
Oluşturma Günü
     │
     ▼ HOT (0–7 gün)
     │   codec: LZ4, shards: 3, replicas: 1
     │   rollover: 10 GB veya 1 gün
     │
     ▼ WARM (7–30 gün)
     │   codec: best_compression, forcemerge: 1 segment, shrink: 1 shard
     │   read-only
     │
     ▼ COLD (30–90 gün)
     │   freeze, replicas: 0
     │
     ▼ DELETE (90. gün)
```

- **SLM Snapshot**: Her gece 02:30'da incremental snapshot → `/data/elasticsearch/backups` (30 gün saklama)

### 4. Görselleştirme — Kibana (Port 5601)

- Data Views: `exchange-msgtrk-*`, `exchange-iis-*`, `exchange-httpproxy-*`, `exchange-mapihttp-*`, `exchange-smtp-receive-*`, `exchange-smtp-send-*`
- Önceden hazırlanmış dashboard: `dashboards/exchange-overview-dashboard.json`

## Disk Mimarisi

```
/                          (sistem diski — 100 GB SSD)
└── OS + binaries + Docker engine

/data                      (2. veri diski — 2 TB NVMe/SSD)
├── docker/                           Docker data-root
├── elasticsearch/
│   ├── data/                         ES index storage
│   ├── logs/                         ES log files
│   └── backups/                      SLM snapshot repository
├── logstash/
│   ├── data/                         Persistent Queue (4 GB)
│   └── dead_letter_queue/            Dead Letter Queue (1 GB)
├── kibana/data/
├── exchange-logs/
│   ├── message-tracking/
│   ├── iis/
│   ├── httpproxy/
│   ├── mapihttp/
│   ├── smtp-receive/
│   └── smtp-send/
└── filebeat-registry/               Filebeat offset kayıtları
```

`scripts/setup-disk.sh` ikinci diski otomatik olarak partition, format, mount eder ve Docker data-root'u taşır.

## Performans Konfigürasyonu

### Elasticsearch (16 GB JVM Heap)
```yaml
ES_JAVA_OPTS: "-Xms16g -Xmx16g"   # 32 GB RAM'in %50'si

number_of_shards: 3
number_of_replicas: 1
refresh_interval: 30s
indices.memory.index_buffer_size: 20%
```

### Logstash (5 pipeline, toplam 9 worker)
```yaml
LS_JAVA_OPTS: "-Xmx4g -Xms4g"

# exchange-router
pipeline.workers: 2  |  batch.size: 1000

# exchange-message-tracking
pipeline.workers: 2  |  batch.size: 500

# exchange-iis
pipeline.workers: 2  |  batch.size: 500

# exchange-http-protocol
pipeline.workers: 2  |  batch.size: 500

# exchange-smtp
pipeline.workers: 1  |  batch.size: 200

queue.type: persisted      # 4 GB
dead_letter_queue: enabled # 1 GB
config.reload.automatic: true
```

### Filebeat (Windows)
```yaml
harvester_buffer_size: 16384
max_bytes: 10485760
scan_frequency: 10s
bulk_max_size: 2048
compression_level: 3
```

## Kapasite Planlama

### 600 Mailbox için Tahminler

#### Günlük Log Hacmi
```
Message Tracking:  ~5.0 GB/gün
IIS Logs:          ~2.0 GB/gün
HttpProxy Logs:    ~1.5 GB/gün
MapiHttp Logs:     ~0.5 GB/gün
SMTP Logs:         ~1.0 GB/gün
─────────────────────────────────
Toplam (ham):      ~10 GB/gün
ES sıkıştırma:     ~3-4 GB/gün (hot), ~1-2 GB/gün (warm/cold)
```

#### Depolama Gereksinimleri (/data üzerinde)
```
7  gün (hot):   ~28 GB
30 gün (warm):  +~65 GB  (sıkıştırılmış)
90 gün (cold):  +~120 GB (freeze)
─────────────────────────────────
Peak toplam:    ~213 GB  (2 TB disk için rahatlıkla yeterli)
Snapshot:       +~70 GB  (30 günlük SLM snapshot)
```

#### Elasticsearch Index Boyutları
```
Daily Index: ~3-5 GB
Weekly Rollover: ~20-35 GB
Monthly Archive: ~85-150 GB
```

### Sistem Kaynakları

#### Memory Usage
```
Elasticsearch: 8-16 GB
Logstash: 4-8 GB
Kibana: 2-4 GB
System: 4 GB
─────────────────
Total: 18-32 GB
```

#### CPU Usage
```
Normal Load: 20-40%
Peak Load: 60-80%
Recommended: 8+ cores
```

#### Disk I/O
```
Random Reads: High (search queries)
Sequential Writes: High (log ingestion)
Recommended: NVMe SSD
```

## Güvenlik Mimarisi

### Network Security
```
Firewall Rules:
- 5601 (Kibana): Restricted to admin IPs
- 9200 (Elasticsearch): Internal only
- 5044 (Logstash): Exchange servers only
- 22 (SSH): Admin access only
```

### Data Protection
```
At Rest:
- Elasticsearch encryption (production)
- Encrypted storage volumes

In Transit:
- TLS for all communication
- VPN for remote access
```

### Access Control
```
Authentication:
- LDAP integration (optional)
- Role-based access control

Authorization:
- Read-only dashboards for users
- Admin access for IT team
```

## Monitoring ve Alerting

### Key Metrics
```
Infrastructure:
- CPU, Memory, Disk usage
- Network throughput
- Container health

Application:
- Ingestion rate
- Query performance  
- Index growth rate
- Pipeline lag
```

### Alert Conditions
```
Critical:
- Service down
- Disk space > 90%
- Memory usage > 95%

Warning:  
- Ingestion lag > 5 minutes
- Query response > 2 seconds
- Disk space > 80%
```

## Backup ve Recovery

### Backup Strategy
```
Elasticsearch Snapshots:
- Daily incremental
- Weekly full backup
- 30-day retention

Configuration Backup:
- Docker configurations
- Kibana dashboards
- Logstash pipelines
```

### Disaster Recovery
```
RTO (Recovery Time Objective): 4 hours
RPO (Recovery Point Objective): 1 hour

Recovery Steps:
1. Restore infrastructure
2. Deploy ELK stack
3. Restore configurations
4. Restore data snapshots
5. Validate functionality
```

## Maintenance Procedures

### Daily Tasks
- Check service health
- Monitor disk usage
- Review error logs
- Validate data ingestion

### Weekly Tasks  
- Performance analysis
- Capacity planning review
- Security log audit
- Backup verification

### Monthly Tasks
- Index optimization
- Configuration review
- Security updates
- Disaster recovery test

## Troubleshooting Framework

### Common Issues

#### Elasticsearch
```
Issue: Cluster red status
Cause: Unassigned shards
Solution: Check node availability, reallocate shards

Issue: High memory usage
Cause: Large heap, heavy queries
Solution: Optimize queries, increase memory
```

#### Logstash
```
Issue: Processing lag
Cause: Slow parsing, insufficient workers  
Solution: Optimize grok patterns, scale workers

Issue: Pipeline errors
Cause: Malformed logs, parsing issues
Solution: Update parsing rules, add error handling
```

#### Filebeat  
```
Issue: Connection failures
Cause: Network issues, authentication
Solution: Check connectivity, verify credentials

Issue: Missing logs
Cause: File permissions, harvester config
Solution: Fix permissions, update configuration
```

## Skalabilite Yol Haritası

### 600 → 1000 Mailboxes
```
Scale Up:
- Memory: 32 → 48 GB
- CPU: 8 → 12 cores
- Storage: 1TB → 2TB
```

### 1000 → 2000 Mailboxes  
```
Scale Out:
- Multi-node Elasticsearch cluster
- Dedicated Logstash nodes
- Load balancing
```

### Enterprise Scale (5000+)
```
Architecture:
- Elasticsearch cluster (3+ nodes)
- Dedicated ingest nodes
- Hot-warm-cold architecture
- Multiple Kibana instances
```