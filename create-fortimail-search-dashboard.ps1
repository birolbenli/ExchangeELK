# FortiMail - Mesaj Arama Dashboard Generator
# Ozellikler:
#   - Input Control filtreler: log_type, severity, from_addr, to_addr, from_domain, client_ip, dst_ip, session_id, subject
#   - Ust: Filtreli kayit sayisi metrigi
#   - Orta: 9 alanli filtre paneli (dropdown)
#   - Alt: 12 sutunlu arama sonuclari (20 satir/sayfa)

Set-StrictMode -Off
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$outPath = Join-Path (Get-Location) "dashboards\fortimail-search-dashboard.ndjson"

$lines = [System.Collections.Generic.List[string]]::new()

# ── 1. Index Pattern (mevcut fm-ip'yi yeniden kullan) ─────────────────────────
$lines.Add('{"id":"fm-ip","type":"index-pattern","managed":false,"attributes":{"title":"fortimail-*","timeFieldName":"@timestamp"},"references":[]}')

# ── 2. Filtreli Kayit Sayisi Metrigi ──────────────────────────────────────────
$lines.Add('{"id":"fm-s-count","type":"visualization","managed":false,"attributes":{"title":"Filtreli Kayit Sayisi","uiStateJSON":"{}","description":"","visState":"{\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"params\":{},\"schema\":\"metric\"}],\"title\":\"Filtreli Kayit Sayisi\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"metric\":{\"labels\":{\"show\":true},\"colorSchema\":\"Green to Red\",\"useRanges\":false,\"style\":{\"labelColor\":false,\"bgFill\":\"#000\",\"fontSize\":60,\"bgColor\":false,\"subText\":\"eslesen kayit\"},\"metricColorMode\":\"None\",\"invertColors\":false,\"colorsRange\":[{\"to\":10000000,\"from\":0}],\"percentageMode\":false},\"type\":\"metric\"},\"type\":\"metric\"}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 3. Spam Sayisi Metrigi ────────────────────────────────────────────────────
$lines.Add('{"id":"fm-s-spam-count","type":"visualization","managed":false,"attributes":{"title":"Spam Kaydi","uiStateJSON":"{}","description":"","visState":"{\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"params\":{},\"schema\":\"metric\"}],\"title\":\"Spam Kaydi\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"metric\":{\"labels\":{\"show\":true},\"colorSchema\":\"Green to Red\",\"useRanges\":false,\"style\":{\"labelColor\":false,\"bgFill\":\"#000\",\"fontSize\":60,\"bgColor\":false,\"subText\":\"spam\"},\"metricColorMode\":\"None\",\"invertColors\":false,\"colorsRange\":[{\"to\":10000000,\"from\":0}],\"percentageMode\":false},\"type\":\"metric\"},\"type\":\"metric\"}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"log_type: spam\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 4. Virus Sayisi Metrigi ───────────────────────────────────────────────────
$lines.Add('{"id":"fm-s-virus-count","type":"visualization","managed":false,"attributes":{"title":"Virus / Sandbox","uiStateJSON":"{}","description":"","visState":"{\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"params\":{},\"schema\":\"metric\"}],\"title\":\"Virus / Sandbox\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"metric\":{\"labels\":{\"show\":true},\"colorSchema\":\"Green to Red\",\"useRanges\":false,\"style\":{\"labelColor\":false,\"bgFill\":\"#000\",\"fontSize\":60,\"bgColor\":false,\"subText\":\"virus\"},\"metricColorMode\":\"None\",\"invertColors\":false,\"colorsRange\":[{\"to\":10000000,\"from\":0}],\"percentageMode\":false},\"type\":\"metric\"},\"type\":\"metric\"}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"log_type: virus\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 5. Auth Hata Sayisi Metrigi ───────────────────────────────────────────────
$lines.Add('{"id":"fm-s-auth-count","type":"visualization","managed":false,"attributes":{"title":"Auth Hatasi","uiStateJSON":"{}","description":"","visState":"{\"aggs\":[{\"id\":\"1\",\"enabled\":true,\"type\":\"count\",\"params\":{},\"schema\":\"metric\"}],\"title\":\"Auth Hatasi\",\"params\":{\"addTooltip\":true,\"addLegend\":false,\"metric\":{\"labels\":{\"show\":true},\"colorSchema\":\"Green to Red\",\"useRanges\":false,\"style\":{\"labelColor\":false,\"bgFill\":\"#000\",\"fontSize\":60,\"bgColor\":false,\"subText\":\"event+failure\"},\"metricColorMode\":\"None\",\"invertColors\":false,\"colorsRange\":[{\"to\":10000000,\"from\":0}],\"percentageMode\":false},\"type\":\"metric\"},\"type\":\"metric\"}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"log_type: event AND event_msg: *failure*\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 6. Input Control Vis (9 filtre alani) ─────────────────────────────────────
# Alan eslesmesi:
#   log_type        => keyword (dogrudan)
#   severity.keyword=> text+keyword subfield
#   from_addr       => keyword
#   to_addr         => keyword
#   from_domain     => keyword
#   client_ip       => ip type (terms destekler)
#   dst_ip.keyword  => text+keyword subfield
#   session_id.keyword => text+keyword subfield
#   subject.keyword => text+keyword subfield
$lines.Add('{"id":"fm-s-controls","type":"visualization","managed":false,"attributes":{"title":"Mesaj Arama Filtreleri","uiStateJSON":"{}","description":"","visState":"{\"type\":\"input_control_vis\",\"aggs\":[],\"title\":\"Mesaj Arama Filtreleri\",\"params\":{\"controls\":[{\"id\":\"1\",\"fieldName\":\"log_type\",\"parent\":\"\",\"label\":\"Log Tipi\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":true,\"dynamicOptions\":true,\"size\":10,\"order\":\"desc\"},\"indexPatternRefName\":\"control_0_index_pattern\"},{\"id\":\"2\",\"fieldName\":\"severity.keyword\",\"parent\":\"\",\"label\":\"Severity\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":true,\"dynamicOptions\":true,\"size\":10,\"order\":\"desc\"},\"indexPatternRefName\":\"control_1_index_pattern\"},{\"id\":\"3\",\"fieldName\":\"from_addr\",\"parent\":\"\",\"label\":\"Gonderen (from_addr)\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_2_index_pattern\"},{\"id\":\"4\",\"fieldName\":\"to_addr\",\"parent\":\"\",\"label\":\"Alici (to_addr)\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_3_index_pattern\"},{\"id\":\"5\",\"fieldName\":\"from_domain\",\"parent\":\"\",\"label\":\"Gonderen Domain\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_4_index_pattern\"},{\"id\":\"6\",\"fieldName\":\"client_ip\",\"parent\":\"\",\"label\":\"Kaynak IP (client_ip)\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_5_index_pattern\"},{\"id\":\"7\",\"fieldName\":\"dst_ip.keyword\",\"parent\":\"\",\"label\":\"Hedef IP (dst_ip)\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_6_index_pattern\"},{\"id\":\"8\",\"fieldName\":\"session_id.keyword\",\"parent\":\"\",\"label\":\"Session ID\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_7_index_pattern\"},{\"id\":\"9\",\"fieldName\":\"subject.keyword\",\"parent\":\"\",\"label\":\"Konu (subject)\",\"type\":\"list\",\"options\":{\"type\":\"terms\",\"multiselect\":false,\"dynamicOptions\":true,\"size\":20,\"order\":\"desc\"},\"indexPatternRefName\":\"control_8_index_pattern\"}],\"updateFiltersOnChange\":false,\"useTimeFilter\":true,\"pinFilters\":false}}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"control_0_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_1_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_2_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_3_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_4_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_5_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_6_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_7_index_pattern","type":"index-pattern"},{"id":"fm-ip","name":"control_8_index_pattern","type":"index-pattern"}]}')

# ── 7. KQL Yardim / Serbest Arama Rehberi ────────────────────────────────────
$lines.Add('{"id":"fm-s-kqlguide","type":"visualization","managed":false,"attributes":{"title":"KQL Serbest Arama Kullanimi","uiStateJSON":"{}","description":"","visState":"{\"aggs\":[],\"title\":\"KQL Serbest Arama Kullanimi\",\"params\":{\"fontSize\":11,\"openLinksInNewTab\":false,\"markdown\":\"#### Ustteki dropdownlar filtreleri uygular. Daha detayli arama icin ust KQL cubuguna yazin:\\n\\n| Alan | KQL Ornegi |\\n|------|-----------|\\n| Konu | subject: *invoice* |\\n| Event metin | event_msg: *failure* |\\n| Session ID | session_id.keyword: 629C8... |\\n| IP aralik | client_ip: 10.11.18.* |\\n| Domain ve tip | log_type: spam AND from_domain: eliptik.com |\\n| Zaman + tip | log_type: virus AND severity.keyword: information |\"},\"type\":\"markdown\"}","kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 8. Arama Sonuclari (saved search, 20 satir/sayfa) ────────────────────────
$lines.Add('{"id":"fm-s-results","type":"search","managed":false,"attributes":{"title":"Mesaj Arama Sonuclari","description":"","hits":0,"columns":["log_type","severity","from_addr","to_addr","from_domain","to_domain","client_ip","dst_ip","subject","event_msg","session_id","device_id"],"sort":[["@timestamp","desc"]],"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"index\":\"fm-ip\",\"highlightAll\":true,\"version\":true,\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},"references":[{"id":"fm-ip","name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern"}]}')

# ── 9. Dashboard Nesnesi ──────────────────────────────────────────────────────
# Layout (48 birim genislik):
#   y=0  h=7:  4x KPI metrigi (w=12 her biri)
#   y=7  h=20: Filtre paneli tam genislik
#   y=27 h=5:  KQL rehberi tam genislik
#   y=32 h=22: Sonuc tablosu tam genislik
$panelsJSON = '[' +
  '{"panelIndex":"1","gridData":{"x":0,"y":0,"w":12,"h":7,"i":"1"},"panelRefName":"panel_1","embeddableConfig":{}},' +
  '{"panelIndex":"2","gridData":{"x":12,"y":0,"w":12,"h":7,"i":"2"},"panelRefName":"panel_2","embeddableConfig":{}},' +
  '{"panelIndex":"3","gridData":{"x":24,"y":0,"w":12,"h":7,"i":"3"},"panelRefName":"panel_3","embeddableConfig":{}},' +
  '{"panelIndex":"4","gridData":{"x":36,"y":0,"w":12,"h":7,"i":"4"},"panelRefName":"panel_4","embeddableConfig":{}},' +
  '{"panelIndex":"5","gridData":{"x":0,"y":7,"w":48,"h":20,"i":"5"},"panelRefName":"panel_5","embeddableConfig":{}},' +
  '{"panelIndex":"6","gridData":{"x":0,"y":27,"w":48,"h":6,"i":"6"},"panelRefName":"panel_6","embeddableConfig":{}},' +
  '{"panelIndex":"7","gridData":{"x":0,"y":33,"w":48,"h":22,"i":"7"},"panelRefName":"panel_7","embeddableConfig":{}}' +
  ']'

$panelsEscaped = $panelsJSON -replace '\\', '\\\\' -replace '"', '\"'
# panelsJSON dogrudan dashboard attributes icerisine koyuldugu icin JSON string olarak girilmeli
# Dashboard nesnesi build:
$dashLine = '{"id":"fm-search-dashboard","type":"dashboard","managed":false,"attributes":{' +
  '"title":"FortiMail - Mesaj Arama Merkezi",' +
  '"description":"Exchange benzeri mesaj arama: log tipi, severity, gonderen, alici, domain, kaynak IP, hedef IP, session ID, konu filtresi",' +
  '"panelsJSON":' + ($panelsJSON | ConvertTo-Json -Compress) + ',' +
  '"optionsJSON":"{\"useMargins\":true,\"syncColors\":true,\"hidePanelTitles\":false}",' +
  '"uiStateJSON":"{}",' +
  '"timeRestore":false,' +
  '"kibanaSavedObjectMeta":{"searchSourceJSON":"{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},' +
  '"references":[' +
  '{"id":"fm-s-count","name":"panel_1","type":"visualization"},' +
  '{"id":"fm-s-spam-count","name":"panel_2","type":"visualization"},' +
  '{"id":"fm-s-virus-count","name":"panel_3","type":"visualization"},' +
  '{"id":"fm-s-auth-count","name":"panel_4","type":"visualization"},' +
  '{"id":"fm-s-controls","name":"panel_5","type":"visualization"},' +
  '{"id":"fm-s-kqlguide","name":"panel_6","type":"visualization"},' +
  '{"id":"fm-s-results","name":"panel_7","type":"search"}' +
  ']}'

$lines.Add($dashLine)

# ── Yaz ──────────────────────────────────────────────────────────────────────
[System.IO.File]::WriteAllLines($outPath, $lines, $utf8NoBom)
Write-Host "Dosya yazildi: $outPath"
Write-Host "Toplam nesne: $($lines.Count)"

# Unique ID dogrulama
$ids = $lines | ForEach-Object {
    if ($_ -match '"id":"([^"]+)"') { $Matches[1] }
}
$dupes = $ids | Group-Object | Where-Object Count -gt 1
if ($dupes) { Write-Host "UYARI - Duplicate IDs: $($dupes.Name -join ', ')" }
else         { Write-Host "ID kontrolu: OK (tekrar eden yok)" }
