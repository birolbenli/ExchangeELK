# Exchange Server DAG ELK Stack Project

Bu proje Exchange Server DAG ortamı için kapsamlı log toplama ve analiz sistemidir.

## Proje Özełlikleri
- 600 mailbox kapasiteli Exchange Server DAG ortamı
- Message tracking, IIS, Virtual Directory, SMTP logları
- Filebeat ile log toplama
- Elasticsearch ile log saklama ve arama
- Logstash ile log işleme
- Kibana ile görselleştirme ve dashboard

## Teknik Gereksinimler
- Ubuntu 20.04+ sunucu
- Minimum 16GB RAM, 4 CPU core
- 500GB SSD disk alanı
- Docker ve Docker Compose

## Deployment
GitHub'dan Ubuntu sunucuya deploy edilecek