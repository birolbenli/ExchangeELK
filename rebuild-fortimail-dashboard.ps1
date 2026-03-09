# ================================================================
# FortiMail Dashboard Paketi - Toplu Yeniden Olusturma
# 2 Dashboard:
#   1. fortimail-dashboard.ndjson          - Email Guvenlik Genel Bakis
#   2. fortimail-analysis-dashboard.ndjson - Log Arastirma Merkezi
#
# Gercek ES alanları (mapping'e gore):
#   keyword   : log_type, from_domain, to_addr, to_domain, from_addr,
#                severity, fm_user, device_id, session_id
#   ip        : client_ip
#   text+kw   : event_msg (.keyword), subject (.keyword), dst_ip (.keyword)
# ================================================================

Set-StrictMode -Off
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function To-Line($obj) { $obj | ConvertTo-Json -Depth 20 -Compress }
function Write-Ndjson($path, $lines) {
    $abs = Join-Path (Get-Location) $path
    [System.IO.File]::WriteAllLines($abs, $lines, $utf8NoBom)
    Write-Host "  -> $path ($($lines.Count) satir)"
}

# ----------------------------------------------------------------
# ORTAK: Index Pattern
# ----------------------------------------------------------------
$ipObj = [ordered]@{
    id="fm-ip"; type="index-pattern"; managed=$false
    attributes=[ordered]@{ title="fortimail-*"; timeFieldName="@timestamp" }
    references=@()
}

# ----------------------------------------------------------------
# YARDIMCI: Metrik vizualizasyon
# ----------------------------------------------------------------
function New-MetricViz($id, $title, $sub, $filterQuery="") {
    $src = if ($filterQuery) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQuery`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}]," +
          "`"title`":`"$title`",`"params`":{`"addTooltip`":true,`"addLegend`":false," +
          "`"metric`":{`"labels`":{`"show`":true},`"colorSchema`":`"Green to Red`"," +
          "`"useRanges`":false,`"style`":{`"labelColor`":false,`"bgFill`":`"#000`"," +
          "`"fontSize`":60,`"bgColor`":false,`"subText`":`"$sub`"}," +
          "`"metricColorMode`":`"None`",`"invertColors`":false," +
          "`"colorsRange`":[{`"to`":10000000,`"from`":0}],`"percentageMode`":false}," +
          "`"type`":`"metric`"},`"type`":`"metric`"}"
    [ordered]@{
        id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{
            title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Terms tablosu (2 seviyeye kadar)
# ----------------------------------------------------------------
function New-TableViz($id, $title, $field, $size=15, $filterQ="", $field2="", $size2=5) {
    $src = if ($filterQ) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
    $agg2 = if ($field2) {
        ",{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field2`"," +
        "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size2,`"otherBucket`":true," +
        "`"otherBucketLabel`":`"Diger`",`"missingBucket`":false},`"schema`":`"bucket`"}"
    } else { "" }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size,`"otherBucket`":false,`"missingBucket`":false}," +
          "`"schema`":`"bucket`"}$agg2],`"title`":`"$title`"," +
          "`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false," +
          "`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null}," +
          "`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
    [ordered]@{
        id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{
            title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Donut pasta
# ----------------------------------------------------------------
function New-PieViz($id, $title, $field, $size=8, $filterQ="") {
    $src = if ($filterQ) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
    $vs = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"}," +
          "{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"$field`"," +
          "`"orderBy`":`"1`",`"order`":`"desc`",`"size`":$size,`"otherBucket`":true," +
          "`"otherBucketLabel`":`"Diger`",`"missingBucket`":false},`"schema`":`"segment`"}]," +
          "`"title`":`"$title`",`"params`":{`"type`":`"pie`",`"addTooltip`":true,`"addLegend`":true," +
          "`"legendPosition`":`"right`",`"isDonut`":true,`"labels`":{`"show`":false,`"values`":true," +
          "`"last_level`":true,`"truncate`":100}},`"type`":`"pie`"}"
    [ordered]@{
        id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{
            title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Stacked histogram (zaman serisi)
# ----------------------------------------------------------------
function New-HistogramViz($id, $title, $splitField, $mode="stacked", $filterQ="") {
    $src = if ($filterQ) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
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
          "`"data`":{`"label`":`"Count`",`"id`":`"1`"},`"valueAxis`":`"ValueAxis-1`"," +
          "`"drawLinesBetweenPoints`":true,`"lineWidth`":2,`"showCircles`":true}]," +
          "`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`"," +
          "`"times`":[],`"addTimeMarker`":false,`"labels`":{},`"thresholdLine`":{`"show`":false}}," +
          "`"type`":`"histogram`"}"
    [ordered]@{
        id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{
            title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Grouped bar (kategorik, zaman degil)
# ----------------------------------------------------------------
function New-GroupedBarViz($id, $title, $xField, $splitField, $filterQ="") {
    $src = if ($filterQ) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
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
    [ordered]@{
        id=$id; type="visualization"; managed=$false
        attributes=[ordered]@{
            title=$title; uiStateJSON="{}"; description=""; visState=$vs
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Saved search
# ----------------------------------------------------------------
function New-Search($id, $title, $cols, $filterQ="") {
    $src = if ($filterQ) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"$filterQ`",`"language`":`"kuery`"},`"filter`":[]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
    [ordered]@{
        id=$id; type="search"; managed=$false
        attributes=[ordered]@{
            title=$title; description=""; hits=0
            columns=$cols
            sort=@(@("@timestamp","desc"))
            kibanaSavedObjectMeta=[ordered]@{ searchSourceJSON=$src }
        }
        references=@([ordered]@{id="fm-ip";name="kibanaSavedObjectMeta.searchSourceJSON.index";type="index-pattern"})
    }
}

# ----------------------------------------------------------------
# YARDIMCI: Dashboard nesnesi
# ----------------------------------------------------------------
function New-Dashboard($id, $title, $desc, $panels, $refs) {
    [ordered]@{
        id=$id; type="dashboard"; managed=$false
        attributes=[ordered]@{
            title=$title; description=$desc
            panelsJSON=($panels | ConvertTo-Json -Depth 10 -Compress)
            optionsJSON="{`"useMargins`":true,`"syncColors`":true,`"hidePanelTitles`":false}"
            uiStateJSON="{}"; timeRestore=$false
            kibanaSavedObjectMeta=[ordered]@{
                searchSourceJSON="{`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
            }
        }
        references=$refs
    }
}

# ================================================================
#  DASHBOARD 1 — "FortiMail - Email Guvenlik Paneli"
# ================================================================
Write-Host "Dashboard 1 olusturuluyor..."
$d1 = @()
$d1 += To-Line $ipObj

# Row 1: KPI metrikleri
$d1 += To-Line (New-MetricViz "fm-v-total"  "Toplam Mail Aktivitesi"     "fortimail-*"  "")
$d1 += To-Line (New-MetricViz "fm-v-spam"   "Spam / Phishing Tespiti"    "spam"         "log_type: spam")
$d1 += To-Line (New-MetricViz "fm-v-virus"  "Virus / Sandbox Alarmi"     "virus+AV"     "log_type: virus")
$d1 += To-Line (New-MetricViz "fm-v-event"  "SMTP Sistem Olaylari"       "event"        "log_type: event")

# Row 2: Stacked trafik + 2 donut
$d1 += To-Line (New-HistogramViz "fm-v-traffic"      "Email Trafigi - Log Turu Bazli"  "log_type"  "stacked")
$d1 += To-Line (New-PieViz       "fm-v-logtype-pie"  "Log Turu Dagilimi"               "log_type"  6)
$d1 += To-Line (New-PieViz       "fm-v-severity-pie" "Severity Dagilimi"               "severity"  6)

# Row 3: Top senders/recipients/IPs
$d1 += To-Line (New-TableViz "fm-v-senders"    "Top Gonderen Domain (Spam)"            "from_domain"       15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-recipients" "Top Hedef Alici (Spam)"                "to_addr"           15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-clientip"   "Top Kaynak IP Adresi (Spam)"           "client_ip"         15 "log_type: spam")

# Row 4: SPF/DKIM + auth fail + kevent
$d1 += To-Line (New-TableViz "fm-v-spfcheck"   "SPF / DKIM / DMARC Sonuclari"         "event_msg.keyword" 15 "log_type: spam")
$d1 += To-Line (New-TableViz "fm-v-authfail"   "SMTP Auth Hatalari (event_msg)"        "event_msg.keyword" 10 "log_type: event AND event_msg: *failure*")
$d1 += To-Line (New-TableViz "fm-v-kevent"     "Admin Degisiklikleri (Kevent)"         "fm_user"           10 "log_type: kevent" "event_msg.keyword" 5)

# Row 5: Saved searches
$d1 += To-Line (New-Search "fm-s-spam"  "Son Spam / Phishing Kayitlari" @("severity","from_addr","to_addr","from_domain","client_ip","subject","event_msg") "log_type: spam")
$d1 += To-Line (New-Search "fm-s-virus" "Son Virus / Sandbox Kayitlari"  @("severity","session_id","device_id","event_msg") "log_type: virus")

# Panel yerlesimi Dashboard 1
$d1Panels = @(
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
$d1Refs = @(
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
$d1 += To-Line (New-Dashboard "fm-dashboard" "FortiMail - Email Guvenlik Paneli" "Genel bakis: spam/virus trendleri, top senderlar, SPF/DKIM sonuclari, severity ozeti, admin audit" $d1Panels $d1Refs)
Write-Ndjson "dashboards\fortimail-dashboard.ndjson" $d1

# ================================================================
#  DASHBOARD 2 — "FortiMail - Log Arastirma Merkezi"
# ================================================================
Write-Host "Dashboard 2 olusturuluyor..."
$d2 = @()
$d2 += To-Line $ipObj   # overwrite:true ile sorunsuz tekrar

# Row 1: KPI metrikleri
$d2 += To-Line (New-MetricViz "fm-a-total"  "Toplam Kayit (Filtreli)"    "zaman filtresi" "")
$d2 += To-Line (New-MetricViz "fm-a-spam"   "Spam Kaydi"                 "spam"    "log_type: spam")
$d2 += To-Line (New-MetricViz "fm-a-virus"  "Virus / Sandbox"            "virus"   "log_type: virus")
$d2 += To-Line (New-MetricViz "fm-a-kevent" "Admin Degisikligi"          "kevent"  "log_type: kevent")

# Row 2: Severity x log_type grouped bar + saatlik stacked
$d2 += To-Line (New-GroupedBarViz "fm-a-sev-bar" "Severity x Log Turu Dagilimi" "severity" "log_type")
$d2 += To-Line (New-HistogramViz  "fm-a-hourly"  "Saatlik Aktivite (Severity renk kodlu)" "severity" "stacked")

# Row 3: Arastirma tablolari
$d2 += To-Line (New-TableViz "fm-a-domain-pair" "Spam: Gonderen Domain -> Alici Domain" "from_domain" 20 "log_type: spam" "to_domain" 5)
$d2 += To-Line (New-TableViz "fm-a-subjects" "Spam: En Cok Gelen Konu Satirlari (subject)" "subject.keyword" 20 "log_type: spam")
$d2 += To-Line (New-TableViz "fm-a-ip-domain" "Spam: Kaynak IP -> Gonderen Domain" "client_ip" 20 "log_type: spam" "from_domain" 5)

# Row 4-9: Detayli saved searches (analist icin tam kolonlar)
$d2 += To-Line (New-Search "fm-a-all"     "[Arastirma] Tum FortiMail Loglari - Tam Gorunum" @("log_type","severity","from_addr","to_addr","from_domain","to_domain","client_ip","subject","event_msg","session_id","device_id"))
$d2 += To-Line (New-Search "fm-a-spam"    "[Arastirma] Spam / Phishing - Detayli Analiz" @("severity","from_addr","to_addr","from_domain","to_domain","client_ip","dst_ip","subject","event_msg","session_id") "log_type: spam")
$d2 += To-Line (New-Search "fm-a-virus"   "[Arastirma] Virus / Sandbox - Detayli Analiz" @("severity","session_id","from_addr","to_addr","subject","event_msg","device_id") "log_type: virus")
$d2 += To-Line (New-Search "fm-a-event"   "[Arastirma] SMTP Event - Sistem ve Baglanti Olaylari" @("severity","client_ip","from_addr","to_addr","event_msg","session_id","device_id") "log_type: event")
$d2 += To-Line (New-Search "fm-a-kevent"  "[Arastirma] Kevent - Admin Audit Trail" @("severity","fm_user","admin_ui","event_msg","device_id") "log_type: kevent")
$d2 += To-Line (New-Search "fm-a-authfail" "[Arastirma] Auth Hatalari / Brute Force Adaylari" @("severity","client_ip","from_addr","to_addr","event_msg","session_id","device_id") "log_type: event AND event_msg: *failure*")

# Panel yerlesimi Dashboard 2
$d2Panels = @(
    @{panelIndex="1"; gridData=@{x=0;y=0;w=12;h=7;i="1"};   embeddableConfig=@{}; panelRefName="panel_1"},
    @{panelIndex="2"; gridData=@{x=12;y=0;w=12;h=7;i="2"};  embeddableConfig=@{}; panelRefName="panel_2"},
    @{panelIndex="3"; gridData=@{x=24;y=0;w=12;h=7;i="3"};  embeddableConfig=@{}; panelRefName="panel_3"},
    @{panelIndex="4"; gridData=@{x=36;y=0;w=12;h=7;i="4"};  embeddableConfig=@{}; panelRefName="panel_4"},
    @{panelIndex="5"; gridData=@{x=0;y=7;w=24;h=13;i="5"};  embeddableConfig=@{}; panelRefName="panel_5"},
    @{panelIndex="6"; gridData=@{x=24;y=7;w=24;h=13;i="6"}; embeddableConfig=@{}; panelRefName="panel_6"},
    @{panelIndex="7"; gridData=@{x=0;y=20;w=16;h=13;i="7"}; embeddableConfig=@{}; panelRefName="panel_7"},
    @{panelIndex="8"; gridData=@{x=16;y=20;w=16;h=13;i="8"};embeddableConfig=@{}; panelRefName="panel_8"},
    @{panelIndex="9"; gridData=@{x=32;y=20;w=16;h=13;i="9"};embeddableConfig=@{}; panelRefName="panel_9"},
    @{panelIndex="10";gridData=@{x=0;y=33;w=48;h=14;i="10"};embeddableConfig=@{};panelRefName="panel_10"},
    @{panelIndex="11";gridData=@{x=0;y=47;w=48;h=14;i="11"};embeddableConfig=@{};panelRefName="panel_11"},
    @{panelIndex="12";gridData=@{x=0;y=61;w=48;h=14;i="12"};embeddableConfig=@{};panelRefName="panel_12"},
    @{panelIndex="13";gridData=@{x=0;y=75;w=48;h=14;i="13"};embeddableConfig=@{};panelRefName="panel_13"},
    @{panelIndex="14";gridData=@{x=0;y=89;w=48;h=14;i="14"};embeddableConfig=@{};panelRefName="panel_14"},
    @{panelIndex="15";gridData=@{x=0;y=103;w=48;h=14;i="15"};embeddableConfig=@{};panelRefName="panel_15"}
)
$d2Refs = @(
    [ordered]@{id="fm-a-total";      name="panel_1";  type="visualization"},
    [ordered]@{id="fm-a-spam";       name="panel_2";  type="visualization"},
    [ordered]@{id="fm-a-virus";      name="panel_3";  type="visualization"},
    [ordered]@{id="fm-a-kevent";     name="panel_4";  type="visualization"},
    [ordered]@{id="fm-a-sev-bar";    name="panel_5";  type="visualization"},
    [ordered]@{id="fm-a-hourly";     name="panel_6";  type="visualization"},
    [ordered]@{id="fm-a-domain-pair";name="panel_7";  type="visualization"},
    [ordered]@{id="fm-a-subjects";   name="panel_8";  type="visualization"},
    [ordered]@{id="fm-a-ip-domain";  name="panel_9";  type="visualization"},
    [ordered]@{id="fm-a-all";        name="panel_10"; type="search"},
    [ordered]@{id="fm-a-spam";       name="panel_11"; type="search"},
    [ordered]@{id="fm-a-virus";      name="panel_12"; type="search"},
    [ordered]@{id="fm-a-event";      name="panel_13"; type="search"},
    [ordered]@{id="fm-a-kevent";     name="panel_14"; type="search"},
    [ordered]@{id="fm-a-authfail";   name="panel_15"; type="search"}
)
$d2 += To-Line (New-Dashboard "fm-analysis-dashboard" "FortiMail - Log Arastirma Merkezi" "Analist odakli: spam/virus/event/kevent detay arama, IP-domain korelasyon, auth hata tespiti, admin audit trail" $d2Panels $d2Refs)
Write-Ndjson "dashboards\fortimail-analysis-dashboard.ndjson" $d2

Write-Host ""
Write-Host "=== TAMAMLANDI ==="
Write-Host "D1: $($d1.Count) nesne  ->  dashboards\fortimail-dashboard.ndjson"
Write-Host "D2: $($d2.Count) nesne  ->  dashboards\fortimail-analysis-dashboard.ndjson"
