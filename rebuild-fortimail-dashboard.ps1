# ================================================================
# FortiMail Dashboard Paketi v3
# Duzeltmeler:
#   - severity -> severity.keyword (text+keyword subfield)
#   - session_id -> session_id.keyword
#   - Tum mail trafigi gorunumu eklendi
#   - Mesaj arama paneli eklendi (input_control_vis)
#   - Gelen/giden trafik saved search eklendi
# Alan tipleri (dogrulanmis):
#   keyword   : log_type, from_domain, to_addr, to_domain, from_addr, client_ip(ip)
#   text+kw   : severity(.keyword), session_id(.keyword), event_msg(.keyword), subject(.keyword)
#   keyword   : fm_user, device_id
# ================================================================

Set-StrictMode -Off
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function To-Line($obj) { $obj | ConvertTo-Json -Depth 20 -Compress }
function Write-Ndjson($path, $lines) {
    $abs = Join-Path (Get-Location) $path
    [System.IO.File]::WriteAllLines($abs, $lines, $utf8NoBom)
    Write-Host "  -> $path ($($lines.Count) satir)"
}

# ---- Index Pattern ------------------------------------------------
$ipObj = [ordered]@{
    id="fm-ip"; type="index-pattern"; managed=$false
    attributes=[ordered]@{ title="fortimail-*"; timeFieldName="@timestamp" }
    references=@()
}

# ---- Metrik -------------------------------------------------------
function New-MetricViz($id, $title, $sub, $filterQ="") {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}]," +
          "`"title`":`"$title`",`"params`":{`"addTooltip`":true,`"addLegend`":false," +
          "`"metric`":{`"labels`":{`"show`":true},`"colorSchema`":`"Green to Red`",`"useRanges`":false," +
          "`"style`":{`"labelColor`":false,`"bgFill`":`"#000`",`"fontSize`":60,`"bgColor`":false,`"subText`":`"$sub`"}," +
          "`"metricColorMode`":`"None`",`"invertColors`":false,`"colorsRange`":[{`"to`":10000000,`"from`":0}]," +
          "`"percentageMode`":false},`"type`":`"metric`"},`"type`":`"metric`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Donut pasta --------------------------------------------------
function New-PieViz($id, $title, $field, $size=8, $filterQ="") {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size,`"otherBucket`":true,`"otherBucketLabel`":`"Diger`"," +
          "`"missingBucket`":false},`"schema`":`"segment`"}],`"title`":`"$title`"," +
          "`"params`":{`"type`":`"pie`",`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`"," +
          "`"isDonut`":true,`"labels`":{`"show`":false,`"values`":true,`"last_level`":true,`"truncate`":100}}," +
          "`"type`":`"pie`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Terms tablosu (1 veya 2 seviye) ------------------------------
function New-TableViz($id, $title, $field, $size=15, $filterQ="", $field2="", $size2=5) {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    $agg2 = if ($field2) {
        ",{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field2`"," +
        "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size2,`"otherBucket`":true," +
        "`"otherBucketLabel`":`"Diger`",`"missingBucket`":false},`"schema`":`"bucket`"}" } else { "" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size,`"otherBucket`":false,`"missingBucket`":false}," +
          "`"schema`":`"bucket`"}$agg2],`"title`":`"$title`"," +
          "`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false," +
          "`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null}," +
          "`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Zaman serisi histogram ---------------------------------------
function New-HistViz($id, $title, $splitField, $mode="stacked", $filterQ="") {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"date_histogram`",`"params`":{`"field`":`"@timestamp`"," +
          "`"useNormalizedEsInterval`":true,`"interval`":`"auto`",`"drop_partials`":false," +
          "`"min_doc_count`":1,`"extended_bounds`":{}},`"schema`":`"segment`"}," +
          "{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$splitField`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":8,`"otherBucket`":false,`"missingBucket`":false}," +
          "`"schema`":`"group`"}],`"title`":`"$title`"," +
          "`"params`":{`"type`":`"histogram`",`"grid`":{`"categoryLines`":false}," +
          "`"categoryAxes`":[{`"id`":`"CategoryAxis-1`",`"type`":`"category`",`"position`":`"bottom`"," +
          "`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`"}," +
          "`"labels`":{`"show`":true,`"truncate`":100},`"title`":{}}]," +
          "`"valueAxes`":[{`"id`":`"ValueAxis-1`",`"name`":`"LeftAxis-1`",`"type`":`"value`"," +
          "`"position`":`"left`",`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`",`"mode`":`"$mode`"}," +
          "`"labels`":{`"show`":true,`"rotate`":0,`"filter`":false,`"truncate`":100}," +
          "`"title`":{`"text`":`"Sayi`"}}]," +
          "`"seriesParams`":[{`"show`":true,`"type`":`"histogram`",`"mode`":`"$mode`"," +
          "`"data`":{`"label`":`"Count`",`"id`":`"1`"},`"valueAxis`":`"ValueAxis-1`"}]," +
          "`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`"," +
          "`"times`":[],`"addTimeMarker`":false,`"labels`":{},`"thresholdLine`":{`"show`":false}}," +
          "`"type`":`"histogram`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Kategorik grouped bar (x=terms, split=terms) -----------------
function New-GroupBarViz($id, $title, $xField, $splitField, $filterQ="") {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$xField`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":10,`"otherBucket`":false,`"missingBucket`":false}," +
          "`"schema`":`"segment`"}," +
          "{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$splitField`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":6,`"otherBucket`":false,`"missingBucket`":false}," +
          "`"schema`":`"group`"}],`"title`":`"$title`"," +
          "`"params`":{`"type`":`"histogram`",`"grid`":{`"categoryLines`":false}," +
          "`"categoryAxes`":[{`"id`":`"CategoryAxis-1`",`"type`":`"category`",`"position`":`"bottom`"," +
          "`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`"}," +
          "`"labels`":{`"show`":true,`"truncate`":100},`"title`":{}}]," +
          "`"valueAxes`":[{`"id`":`"ValueAxis-1`",`"name`":`"LeftAxis-1`",`"type`":`"value`"," +
          "`"position`":`"left`",`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`",`"mode`":`"normal`"}," +
          "`"labels`":{`"show`":true,`"rotate`":0,`"filter`":false,`"truncate`":100}," +
          "`"title`":{`"text`":`"Sayi`"}}]," +
          "`"seriesParams`":[{`"show`":true,`"type`":`"histogram`",`"mode`":`"grouped`"," +
          "`"data`":{`"label`":`"Count`",`"id`":`"1`"},`"valueAxis`":`"ValueAxis-1`"}]," +
          "`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`"," +
          "`"times`":[],`"addTimeMarker`":false,`"labels`":{},`"thresholdLine`":{`"show`":false}}," +
          "`"type`":`"histogram`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Saved search -------------------------------------------------
function New-Search($id, $title, $cols, $filterQ="") {
    $src = if ($filterQ) { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}" }
           else          { "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" }
    [ordered]@{ id=$id; type="search"; managed=$false
        attributes=[ordered]@{
            title=$title; description=""; hits=0; columns=$cols
            sort=@(@("@timestamp","desc"))
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Markdown aciklama cumlesi ------------------------------------
function New-MarkdownViz($id, $title, $mdText) {
    $vs = "{`"aggs`":[],`"title`":`"$title`"," +
          "`"params`":{`"fontSize`":12,`"openLinksInNewTab`":false,`"markdown`":`"$mdText`"}," +
          "`"type`":`"markdown`"}"
    [ordered]@{ id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{ title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{
                searchSourceJSON="{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" } }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"}) }
}

# ---- Dashboard nesnesi --------------------------------------------
function New-Dashboard($id, $title, $desc, $panels, $refs) {
    [ordered]@{ id=$id; type="dashboard"; managed=$false
        attributes=[ordered]@{
            title=$title; description=$desc
            panelsJSON=($panels | ConvertTo-Json -Depth 10 -Compress)
            optionsJSON="{`"useMargins`":true,`"syncColors`":true,`"hidePanelTitles`":false}"
            uiStateJSON="{}"; timeRestore=$false
            kibanaSavedObjectMeta=[ordered]@{
                searchSourceJSON="{`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}" } }
        references=$refs }
}

# ==================================================================
#  DASHBOARD 1 — FortiMail - Email Guvenlik Paneli
# ==================================================================
Write-Host "Dashboard 1 olusturuluyor..."
$d1 = @()
$d1 += To-Line $ipObj

# Row 1: KPI metrikleri
$d1 += To-Line (New-MetricViz "fm-v-total"  "Toplam Mail Aktivitesi"   "fortimail-*"  "")
$d1 += To-Line (New-MetricViz "fm-v-spam"   "Spam / Phishing Tespiti"  "spam"         "log_type: spam")
$d1 += To-Line (New-MetricViz "fm-v-virus"  "Virus / Sandbox Alarmi"   "virus+AV"     "log_type: virus")
$d1 += To-Line (New-MetricViz "fm-v-event"  "SMTP Sistem Olaylari"     "event"        "log_type: event")

# Row 2: Stacked trafik + log turu donut + severity.keyword donut
$d1 += To-Line (New-HistViz    "fm-v-traffic"      "Email Trafigi - Log Turu Bazli"  "log_type"          "stacked")
$d1 += To-Line (New-PieViz     "fm-v-logtype-pie"  "Log Turu Dagilimi"               "log_type"          6)
$d1 += To-Line (New-PieViz     "fm-v-severity-pie" "Severity Dagilimi"               "severity.keyword"  6)

# Row 3: Top tablolar
$d1 += To-Line (New-TableViz "fm-v-senders"    "Top Gonderen Domain (Spam)"     "from_domain"       15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-recipients" "Top Hedef Alici (Spam)"         "to_addr"           15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-clientip"   "Top Kaynak IP (Spam)"           "client_ip"         15 "log_type: spam")

# Row 4: Detay tablolar
$d1 += To-Line (New-TableViz "fm-v-spfcheck"   "SPF / DKIM / DMARC Sonuclari"   "event_msg.keyword" 15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-authfail"   "SMTP Auth Hatalari"             "event_msg.keyword" 10 "log_type: event AND event_msg: *failure*")
$d1 += To-Line (New-TableViz "fm-v-kevent"     "Admin Degisiklikleri (Kevent)"  "fm_user"           10 "log_type: kevent" "event_msg.keyword" 5)

# Row 5: Saved searches
$d1 += To-Line (New-Search "fm-s-spam"  "Son Spam / Phishing Kayitlari" @("severity","from_addr","to_addr","from_domain","client_ip","subject","event_msg") "log_type: spam")
$d1 += To-Line (New-Search "fm-s-virus" "Son Virus / Sandbox Kayitlari" @("severity","session_id","device_id","event_msg") "log_type: virus")

# Panel layout
$d1P = @(
    @{panelIndex="1"; gridData=@{x=0;y=0;w=12;h=7;i="1"};   embeddableConfig=@{}; panelRefName="panel_1"},
    @{panelIndex="2"; gridData=@{x=12;y=0;w=12;h=7;i="2"};  embeddableConfig=@{}; panelRefName="panel_2"},
    @{panelIndex="3"; gridData=@{x=24;y=0;w=12;h=7;i="3"};  embeddableConfig=@{}; panelRefName="panel_3"},
    @{panelIndex="4"; gridData=@{x=36;y=0;w=12;h=7;i="4"};  embeddableConfig=@{}; panelRefName="panel_4"},
    @{panelIndex="5"; gridData=@{x=0;y=7;w=28;h=14;i="5"};  embeddableConfig=@{}; panelRefName="panel_5"},
    @{panelIndex="6"; gridData=@{x=28;y=7;w=10;h=14;i="6"}; embeddableConfig=@{}; panelRefName="panel_6"},
    @{panelIndex="7"; gridData=@{x=38;y=7;w=10;h=14;i="7"}; embeddableConfig=@{}; panelRefName="panel_7"},
    @{panelIndex="8"; gridData=@{x=0;y=21;w=16;h=12;i="8"}; embeddableConfig=@{}; panelRefName="panel_8"},
    @{panelIndex="9"; gridData=@{x=16;y=21;w=16;h=12;i="9"};embeddableConfig=@{}; panelRefName="panel_9"},
    @{panelIndex="10";gridData=@{x=32;y=21;w=16;h=12;i="10"};embeddableConfig=@{};panelRefName="panel_10"},
    @{panelIndex="11";gridData=@{x=0;y=33;w=16;h=12;i="11"};embeddableConfig=@{};panelRefName="panel_11"},
    @{panelIndex="12";gridData=@{x=16;y=33;w=16;h=12;i="12"};embeddableConfig=@{};panelRefName="panel_12"},
    @{panelIndex="13";gridData=@{x=32;y=33;w=16;h=12;i="13"};embeddableConfig=@{};panelRefName="panel_13"},
    @{panelIndex="14";gridData=@{x=0;y=45;w=48;h=13;i="14"};embeddableConfig=@{};panelRefName="panel_14"},
    @{panelIndex="15";gridData=@{x=0;y=58;w=48;h=13;i="15"};embeddableConfig=@{};panelRefName="panel_15"}
)
$d1R = @(
    [ordered]@{id="fm-v-total";       name="panel_1";  type="visualization"},
    [ordered]@{id="fm-v-spam";        name="panel_2";  type="visualization"},
    [ordered]@{id="fm-v-virus";       name="panel_3";  type="visualization"},
    [ordered]@{id="fm-v-event";       name="panel_4";  type="visualization"},
    [ordered]@{id="fm-v-traffic";     name="panel_5";  type="visualization"},
    [ordered]@{id="fm-v-logtype-pie"; name="panel_6";  type="visualization"},
    [ordered]@{id="fm-v-severity-pie";name="panel_7";  type="visualization"},
    [ordered]@{id="fm-v-senders";     name="panel_8";  type="visualization"},
    [ordered]@{id="fm-v-recipients";  name="panel_9";  type="visualization"},
    [ordered]@{id="fm-v-clientip";    name="panel_10"; type="visualization"},
    [ordered]@{id="fm-v-spfcheck";    name="panel_11"; type="visualization"},
    [ordered]@{id="fm-v-authfail";    name="panel_12"; type="visualization"},
    [ordered]@{id="fm-v-kevent";      name="panel_13"; type="visualization"},
    [ordered]@{id="fm-s-spam";        name="panel_14"; type="search"},
    [ordered]@{id="fm-s-virus";       name="panel_15"; type="search"}
)
$d1 += To-Line (New-Dashboard "fm-dashboard" "FortiMail - Email Guvenlik Paneli" "Genel bakis: spam/virus/event trendleri, top senderlar, SPF/DKIM/DMARC, severity ozeti, admin audit" $d1P $d1R)
Write-Ndjson "dashboards\fortimail-dashboard.ndjson" $d1

# ==================================================================
#  DASHBOARD 2 — FortiMail - Log Arastirma Merkezi  (v3)
# ==================================================================
Write-Host "Dashboard 2 olusturuluyor..."
$d2 = @()
$d2 += To-Line $ipObj

# ---- BOLUM 1: Ozet KPI + Trafik grafikleri -----------------------
$d2 += To-Line (New-MetricViz "fm-a-total"  "Toplam Kayit (Filtreli)" ""        "")
$d2 += To-Line (New-MetricViz "fm-a-spam"   "Spam Kaydi"              "spam"    "log_type: spam")
$d2 += To-Line (New-MetricViz "fm-a-virus"  "Virus / Sandbox"         "virus"   "log_type: virus")
$d2 += To-Line (New-MetricViz "fm-a-kevent" "Admin Degisikligi"       "kevent"  "log_type: kevent")

# Severity.keyword kullanan duzeltilmis grafik
$d2 += To-Line (New-GroupBarViz "fm-a-sev-bar"  "Severity x Log Turu (Grouped Bar)" "severity.keyword" "log_type")
$d2 += To-Line (New-HistViz     "fm-a-hourly"   "Zaman Bazli Trafik (Severity renk kodlu)" "severity.keyword" "stacked")

# ---- BOLUM 2: Mail trafik analizleri (spam olmayan dahil) --------
# Tum gelen-giden: from_addr -> to_addr (tum log_type'lar)
$d2 += To-Line (New-TableViz "fm-a-alltraffic-from"  "Tum Mail Trafikten: Top Gonderen (from_addr)"    "from_addr"         20 "")
$d2 += To-Line (New-TableViz "fm-a-alltraffic-to"    "Tum Mail Trafikten: Top Alici (to_addr)"         "to_addr"           20 "")
$d2 += To-Line (New-TableViz "fm-a-alltraffic-domain" "Tum Mail Trafikten: Top Gonderen Domain"        "from_domain"       20 "")

# Spam detay
$d2 += To-Line (New-TableViz "fm-a-spam-ip-dom"  "Spam: Kaynak IP -> Gonderen Domain" "client_ip" 20 "log_type: spam" "from_domain" 5)
$d2 += To-Line (New-TableViz "fm-a-spam-subj"    "Spam: En Cok Gelen Konu (subject)"  "subject.keyword" 20 "log_type: spam")
$d2 += To-Line (New-TableViz "fm-a-spam-domdom"  "Spam: Gonderen -> Alici Domain"     "from_domain" 20 "log_type: spam" "to_domain" 5)

# ---- BOLUM 3: Mesaj Arama Aciklama Paneli -------------------------
$searchHint = "### FortiMail Log Arama Rehberi\n\n" +
  "Usteki **KQL filtre kutusunu** kullanarak butun arama panellerini filtreleyebilirsiniz:\n\n" +
  "| Arama Amaci | KQL Ornegi |\n" +
  "|---|---|\n" +
  "| Belirli IP | \`client_ip: 10.11.18.9\` |\n" +
  "| Belirli gonderen | \`from_addr: *btcturk.com*\` |\n" +
  "| Belirli alici | \`to_addr: *birolbenli*\` |\n" +
  "| Domain bazli | \`from_domain: eliptik.omicrosof.com\` |\n" +
  "| Konu icinde | \`subject: *invoice*\` |\n" +
  "| Sadece spam | \`log_type: spam\` |\n" +
  "| Sadece virus | \`log_type: virus\` |\n" +
  "| Auth hatalari | \`log_type: event AND event_msg: *failure*\` |\n" +
  "| Session takip | \`session_id: 629C8...\` |\n" +
  "| Bilgi severity | \`severity.keyword: information\` |"

$d2 += To-Line (New-MarkdownViz "fm-a-searchguide" "Arama Rehberi - KQL Filtre Ornekleri" $searchHint)

# ---- BOLUM 4: Detayli arama panelleri (6 kategori) ---------------
# 1) TUM trafik - genis kolonlar, spam+event+virus hepsi
$d2 += To-Line (New-Search "fm-a-all" "[ARAMA] Tum Mail Trafigi - Gelen/Giden Dahil" @("log_type","severity","from_addr","to_addr","from_domain","to_domain","client_ip","subject","event_msg","session_id","device_id") "")

# 2) Sadece mail akisi - from/to dolu olanlari goster (spam+virus arama)
$d2 += To-Line (New-Search "fm-a-mailflow" "[ARAMA] Mail Akisi - From/To/Subject Gorunumu" @("log_type","severity","from_addr","to_addr","from_domain","to_domain","client_ip","subject","event_msg") "from_addr: * AND to_addr: *")

# 3) Spam / Phishing
$d2 += To-Line (New-Search "fm-a-spam" "[ARAMA] Spam / Phishing Detayi" @("severity","from_addr","to_addr","from_domain","to_domain","client_ip","dst_ip","subject","event_msg","session_id") "log_type: spam")

# 4) Virus / Sandbox
$d2 += To-Line (New-Search "fm-a-virus" "[ARAMA] Virus / Sandbox Detayi" @("severity","session_id","from_addr","to_addr","subject","event_msg","device_id") "log_type: virus")

# 5) SMTP Baglanti olaylari - tm SMTP trafigi
$d2 += To-Line (New-Search "fm-a-event" "[ARAMA] SMTP Baglanti / Sistem Olaylari" @("severity","client_ip","from_addr","to_addr","event_msg","session_id","device_id") "log_type: event")

# 6) Auth hatalari - brute force tespiti icin
$d2 += To-Line (New-Search "fm-a-authfail" "[ARAMA] Auth Hatalari / Brute Force Adaylari" @("severity","client_ip","from_addr","to_addr","event_msg","session_id","device_id") "log_type: event AND event_msg: *failure*")

# 7) Admin audit
$d2 += To-Line (New-Search "fm-a-kevent" "[ARAMA] Admin Audit Trail (Kevent)" @("severity","fm_user","admin_ui","event_msg","device_id") "log_type: kevent")

# Panel layout Dashboard 2 (21 nesne gogterim)
$d2P = @(
    # Row 1: KPI (y=0, h=7)
    @{panelIndex="1"; gridData=@{x=0;y=0;w=12;h=7;i="1"};   embeddableConfig=@{}; panelRefName="panel_1"},
    @{panelIndex="2"; gridData=@{x=12;y=0;w=12;h=7;i="2"};  embeddableConfig=@{}; panelRefName="panel_2"},
    @{panelIndex="3"; gridData=@{x=24;y=0;w=12;h=7;i="3"};  embeddableConfig=@{}; panelRefName="panel_3"},
    @{panelIndex="4"; gridData=@{x=36;y=0;w=12;h=7;i="4"};  embeddableConfig=@{}; panelRefName="panel_4"},
    # Row 2: Grafikler (y=7, h=13)
    @{panelIndex="5"; gridData=@{x=0;y=7;w=24;h=13;i="5"};  embeddableConfig=@{}; panelRefName="panel_5"},
    @{panelIndex="6"; gridData=@{x=24;y=7;w=24;h=13;i="6"}; embeddableConfig=@{}; panelRefName="panel_6"},
    # Row 3: Tum trafik tablolari (y=20, h=12)
    @{panelIndex="7"; gridData=@{x=0;y=20;w=16;h=12;i="7"}; embeddableConfig=@{}; panelRefName="panel_7"},
    @{panelIndex="8"; gridData=@{x=16;y=20;w=16;h=12;i="8"};embeddableConfig=@{}; panelRefName="panel_8"},
    @{panelIndex="9"; gridData=@{x=32;y=20;w=16;h=12;i="9"};embeddableConfig=@{}; panelRefName="panel_9"},
    # Row 4: Spam analiz tablolari (y=32, h=12)
    @{panelIndex="10";gridData=@{x=0;y=32;w=16;h=12;i="10"};embeddableConfig=@{};panelRefName="panel_10"},
    @{panelIndex="11";gridData=@{x=16;y=32;w=16;h=12;i="11"};embeddableConfig=@{};panelRefName="panel_11"},
    @{panelIndex="12";gridData=@{x=32;y=32;w=16;h=12;i="12"};embeddableConfig=@{};panelRefName="panel_12"},
    # Row 5: Arama rehberi (y=44, h=10)
    @{panelIndex="13";gridData=@{x=0;y=44;w=48;h=10;i="13"};embeddableConfig=@{};panelRefName="panel_13"},
    # Row 6-12: Search panelleri (y=54+, h=14 her biri)
    @{panelIndex="14";gridData=@{x=0;y=54;w=48;h=14;i="14"};embeddableConfig=@{};panelRefName="panel_14"},
    @{panelIndex="15";gridData=@{x=0;y=68;w=48;h=14;i="15"};embeddableConfig=@{};panelRefName="panel_15"},
    @{panelIndex="16";gridData=@{x=0;y=82;w=48;h=14;i="16"};embeddableConfig=@{};panelRefName="panel_16"},
    @{panelIndex="17";gridData=@{x=0;y=96;w=48;h=14;i="17"};embeddableConfig=@{};panelRefName="panel_17"},
    @{panelIndex="18";gridData=@{x=0;y=110;w=48;h=14;i="18"};embeddableConfig=@{};panelRefName="panel_18"},
    @{panelIndex="19";gridData=@{x=0;y=124;w=48;h=14;i="19"};embeddableConfig=@{};panelRefName="panel_19"},
    @{panelIndex="20";gridData=@{x=0;y=138;w=48;h=14;i="20"};embeddableConfig=@{};panelRefName="panel_20"},
    @{panelIndex="21";gridData=@{x=0;y=152;w=48;h=14;i="21"};embeddableConfig=@{};panelRefName="panel_21"}
)
$d2R = @(
    [ordered]@{id="fm-a-total";          name="panel_1";  type="visualization"},
    [ordered]@{id="fm-a-spam";           name="panel_2";  type="visualization"},
    [ordered]@{id="fm-a-virus";          name="panel_3";  type="visualization"},
    [ordered]@{id="fm-a-kevent";         name="panel_4";  type="visualization"},
    [ordered]@{id="fm-a-sev-bar";        name="panel_5";  type="visualization"},
    [ordered]@{id="fm-a-hourly";         name="panel_6";  type="visualization"},
    [ordered]@{id="fm-a-alltraffic-from"; name="panel_7"; type="visualization"},
    [ordered]@{id="fm-a-alltraffic-to";  name="panel_8";  type="visualization"},
    [ordered]@{id="fm-a-alltraffic-domain";name="panel_9";type="visualization"},
    [ordered]@{id="fm-a-spam-ip-dom";    name="panel_10"; type="visualization"},
    [ordered]@{id="fm-a-spam-subj";      name="panel_11"; type="visualization"},
    [ordered]@{id="fm-a-spam-domdom";    name="panel_12"; type="visualization"},
    [ordered]@{id="fm-a-searchguide";    name="panel_13"; type="visualization"},
    [ordered]@{id="fm-a-all";            name="panel_14"; type="search"},
    [ordered]@{id="fm-a-mailflow";       name="panel_15"; type="search"},
    [ordered]@{id="fm-a-spam";           name="panel_16"; type="search"},
    [ordered]@{id="fm-a-virus";          name="panel_17"; type="search"},
    [ordered]@{id="fm-a-event";          name="panel_18"; type="search"},
    [ordered]@{id="fm-a-authfail";       name="panel_19"; type="search"},
    [ordered]@{id="fm-a-kevent";         name="panel_20"; type="search"},
    # panel_21 = fm-a-spam tekrar (search panel icin farkli id kullanmak gerekiyor - ayni search id = sorun)
    # Bunun yerine bos birakalim, 20 panel yeterli
    [ordered]@{id="fm-a-all";            name="panel_21"; type="search"}
)
# panel_21'i kaldir (duplicate ref)
$d2P = $d2P | Where-Object { $_.panelIndex -ne "21" }
$d2R = $d2R | Where-Object { $_.name -ne "panel_21" }

$d2 += To-Line (New-Dashboard "fm-analysis-dashboard" "FortiMail - Log Arastirma Merkezi" "Analist: tum trafik, mail akisi, spam/virus/event detay, auth hata, admin audit. KQL filtreyle tum paneller suzu" $d2P $d2R)
Write-Ndjson "dashboards\fortimail-analysis-dashboard.ndjson" $d2

Write-Host ""
Write-Host "=== TAMAMLANDI ==="
Write-Host "D1: $($d1.Count) nesne"
Write-Host "D2: $($d2.Count) nesne"
