# ================================================================
# FortiMail Dashboard Yeniden Olusturma Scripti
# Gercek ES alanlarına gore optimize edilmistir:
#   - from_domain, to_addr, client_ip (spam)
#   - fm_user, admin_ui (event/kevent)
#   - log_type (tum indexler)
#   - event_msg (tum indexler)
# ================================================================

$outFile = "dashboards\fortimail-dashboard.ndjson"
$lines = @()

# ---- Yardimci: Nesneyi tek satir JSON'a cevir --------------------
function To-Line($obj) {
    return ($obj | ConvertTo-Json -Depth 20 -Compress)
}

# ---- 1. Index Pattern -------------------------------------------
$ip = [ordered]@{
    id   = "fm-ip"
    type = "index-pattern"
    attributes = [ordered]@{
        title         = "fortimail-*"
        timeFieldName = "@timestamp"
    }
    references   = @()
    managed      = $false
}
$lines += To-Line $ip

# ---- Yardimci: visState JSON builder ----------------------------
function Make-MetricVis($id, $title, $subText, $filterJson = "") {
    $searchSrc = if ($filterJson) {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[$filterJson]}"
    } else {
        "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
    }
    $visState = "{`"aggs`":[{`"params`":{},`"schema`":`"metric`",`"id`":`"1`",`"type`":`"count`",`"enabled`":true}],`"title`":`"$title`",`"params`":{`"addTooltip`":true,`"addLegend`":false,`"metric`":{`"labels`":{`"show`":true},`"colorSchema`":`"Green to Red`",`"useRanges`":false,`"style`":{`"labelColor`":false,`"bgFill`":`"#000`",`"fontSize`":60,`"bgColor`":false,`"subText`":`"$subText`"},`"metricColorMode`":`"None`",`"invertColors`":false,`"colorsRange`":[{`"to`":10000000,`"from`":0}],`"percentageMode`":false},`"type`":`"metric`"},`"type`":`"metric`"}"
    return [ordered]@{
        id   = $id
        type = "visualization"
        attributes = [ordered]@{
            title       = $title
            uiStateJSON = "{}"
            description = ""
            visState    = $visState
            kibanaSavedObjectMeta = [ordered]@{
                searchSourceJSON = $searchSrc
            }
        }
        references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
        managed = $false
    }
}

# ---- 2. Metrik: Toplam Kayit ------------------------------------
$lines += To-Line (Make-MetricVis "fm-viz-total-count" "Toplam FortiMail Kaydi" "Tum Loglar")

# ---- 3. Metrik: Spam --------------------------------------------
$spamFilter = "{`"meta`":{`"index`":`"fm-ip`",`"negate`":false,`"disabled`":false,`"alias`":null,`"type`":`"phrase`",`"key`":`"log_type`",`"value`":`"spam`"},`"query`":{`"match_phrase`":{`"log_type`":`"spam`"}}}"
$lines += To-Line (Make-MetricVis "fm-viz-spam-count" "Spam Tespiti" "spam" $spamFilter)

# ---- 4. Metrik: Virus -------------------------------------------
$virusFilter = "{`"meta`":{`"index`":`"fm-ip`",`"negate`":false,`"disabled`":false,`"alias`":null,`"type`":`"phrase`",`"key`":`"log_type`",`"value`":`"virus`"},`"query`":{`"match_phrase`":{`"log_type`":`"virus`"}}}"
$lines += To-Line (Make-MetricVis "fm-viz-virus-count" "Virus / Sandbox Tespiti" "virus+sandbox" $virusFilter)

# ---- 5. Metrik: SMTP Event --------------------------------------
$eventFilter = "{`"meta`":{`"index`":`"fm-ip`",`"negate`":false,`"disabled`":false,`"alias`":null,`"type`":`"phrase`",`"key`":`"log_type`",`"value`":`"event`"},`"query`":{`"match_phrase`":{`"log_type`":`"event`"}}}"
$lines += To-Line (Make-MetricVis "fm-viz-event-count" "SMTP Events" "event" $eventFilter)

# ---- 6. Zaman Serisi: log_type bazli ----------------------------
$trafficVis = [ordered]@{
    id   = "fm-viz-traffic-time"
    type = "visualization"
    attributes = [ordered]@{
        title       = "FortiMail - Log Turu Bazli Trafik"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"date_histogram`",`"params`":{`"field`":`"@timestamp`",`"timeRange`":{`"from`":`"now-24h`",`"to`":`"now`"},`"useNormalizedEsInterval`":true,`"scaleMetricValues`":false,`"interval`":`"auto`",`"drop_partials`":false,`"min_doc_count`":1,`"extended_bounds`":{}},`"schema`":`"segment`"},{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"log_type.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":5,`"otherBucket`":false,`"otherBucketLabel`":`"Other`",`"missingBucket`":false,`"missingBucketLabel`":`"Missing`"},`"schema`":`"group`"}],`"title`":`"FortiMail - Log Turu Bazli Trafik`",`"params`":{`"type`":`"histogram`",`"grid`":{`"categoryLines`":false},`"categoryAxes`":[{`"id`":`"CategoryAxis-1`",`"type`":`"category`",`"position`":`"bottom`",`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`"},`"labels`":{`"show`":true,`"truncate`":100},`"title`":{}}],`"valueAxes`":[{`"id`":`"ValueAxis-1`",`"name`":`"LeftAxis-1`",`"type`":`"value`",`"position`":`"left`",`"show`":true,`"style`":{},`"scale`":{`"type`":`"linear`",`"mode`":`"normal`"},`"labels`":{`"show`":true,`"rotate`":0,`"filter`":false,`"truncate`":100},`"title`":{`"text`":`"Sayi`"}}],`"seriesParams`":[{`"show`":true,`"type`":`"histogram`",`"mode`":`"stacked`",`"data`":{`"label`":`"Count`",`"id`":`"1`"},`"valueAxis`":`"ValueAxis-1`",`"drawLinesBetweenPoints`":true,`"lineWidth`":2,`"interpolate`":`"linear`",`"showCircles`":true}],`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`",`"times`":[],`"addTimeMarker`":false,`"labels`":{},`"thresholdLine`":{`"show`":false,`"value`":10,`"width`":1,`"style`":`"full`",`"color`":`"#E7664C`"}},`"type`":`"histogram`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $trafficVis

# ---- 7. Log Turu Pasta ------------------------------------------
$logtypePie = [ordered]@{
    id   = "fm-viz-logtype-pie"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Log Turu Dagilimi"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"log_type.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":10,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"segment`"}],`"title`":`"Log Turu Dagilimi`",`"params`":{`"type`":`"pie`",`"addTooltip`":true,`"addLegend`":true,`"legendPosition`":`"right`",`"isDonut`":true,`"labels`":{`"show`":false,`"values`":true,`"last_level`":true,`"truncate`":100}},`"type`":`"pie`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $logtypePie

# ---- 8. Top Gonderen Domain (spam'de from_domain) ---------------
$topSendersVis = [ordered]@{
    id   = "fm-viz-top-senders"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Top Gonderen Domain (Spam)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"from_domain.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":15,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"Top Gonderen Domain (Spam)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: spam`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $topSendersVis

# ---- 9. Top Alici (spam'de to_addr) ----------------------------
$topRecipientsVis = [ordered]@{
    id   = "fm-viz-top-recipients"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Top Alici (Spam)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"to_addr.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":15,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"Top Alici (Spam)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: spam`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $topRecipientsVis

# ---- 10. Top Kaynak IP (spam'de client_ip) ----------------------
$topClientIPVis = [ordered]@{
    id   = "fm-viz-top-client-ip"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Top Kaynak IP (Spam)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"client_ip.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":15,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"Top Kaynak IP (Spam)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: spam`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $topClientIPVis

# ---- 11. Spam Kontrol Sonuclari (event_msg iceriginden) ---------
$spamChecksVis = [ordered]@{
    id   = "fm-viz-spam-checks"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Spam Kontrol Sonuclari (SPF/DKIM/vb)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"event_msg.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":15,`"otherBucket`":true,`"otherBucketLabel`":`"Diger`",`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"Spam Kontrol Sonuclari (SPF/DKIM/vb)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: spam`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $spamChecksVis

# ---- 12. SMTP Auth Hatalari (event_msg'de failure) ---------------
$authFailVis = [ordered]@{
    id   = "fm-viz-auth-fail"
    type = "visualization"
    attributes = [ordered]@{
        title       = "SMTP Auth Hatalari (Top IP)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"event_msg.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":10,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"SMTP Auth Hatalari (Top IP)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: event AND event_msg: *failure*`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $authFailVis

# ---- 13. Kevent - Admin Degisiklikleri ---------------------------
$keventVis = [ordered]@{
    id   = "fm-viz-kevent-users"
    type = "visualization"
    attributes = [ordered]@{
        title       = "Admin Degisiklikleri (Kevent)"
        uiStateJSON = "{}"
        description = ""
        visState    = "{`"aggs`":[{`"id`":`"1`",`"enabled`":true,`"type`":`"count`",`"params`":{},`"schema`":`"metric`"},{`"id`":`"2`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"fm_user.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":10,`"otherBucket`":false,`"missingBucket`":false},`"schema`":`"bucket`"},{`"id`":`"3`",`"enabled`":true,`"type`":`"terms`",`"params`":{`"field`":`"event_msg.keyword`",`"orderBy`":`"1`",`"order`":`"desc`",`"size`":5,`"otherBucket`":true,`"otherBucketLabel`":`"Diger`",`"missingBucket`":false},`"schema`":`"bucket`"}],`"title`":`"Admin Degisiklikleri (Kevent)`",`"params`":{`"type`":`"table`",`"perPage`":10,`"showPartialRows`":false,`"showMetricsAtAllLevels`":false,`"sort`":{`"columnIndex`":null,`"direction`":null},`"showTotal`":false,`"totalFunc`":`"sum`",`"percentageCol`":`"`"},`"type`":`"table`"}"
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: kevent`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $keventVis

# ---- 14. Saved Search: Tum FortiMail ----------------------------
$savedSearchAll = [ordered]@{
    id   = "fm-saved-search"
    type = "search"
    attributes = [ordered]@{
        title           = "FortiMail - Tum Loglar"
        description     = ""
        hits            = 0
        columns         = @("log_type","severity","from_addr","to_addr","client_ip","event_msg","device_id")
        sort            = @(@("@timestamp","desc"))
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $savedSearchAll

# ---- 15. Saved Search: Spam ------------------------------------
$savedSearchSpam = [ordered]@{
    id   = "fm-saved-search-spam"
    type = "search"
    attributes = [ordered]@{
        title           = "FortiMail - Spam Loglar"
        description     = ""
        hits            = 0
        columns         = @("severity","from_addr","to_addr","from_domain","client_ip","subject","event_msg")
        sort            = @(@("@timestamp","desc"))
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: spam`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $savedSearchSpam

# ---- 16. Saved Search: Virus -----------------------------------
$savedSearchVirus = [ordered]@{
    id   = "fm-saved-search-virus"
    type = "search"
    attributes = [ordered]@{
        title           = "FortiMail - Virus/Sandbox Loglar"
        description     = ""
        hits            = 0
        columns         = @("severity","session_id","event_msg","device_id")
        sort            = @(@("@timestamp","desc"))
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"index`":`"fm-ip`",`"query`":{`"query`":`"log_type: virus`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = @([ordered]@{ id="fm-ip"; name="kibanaSavedObjectMeta.searchSourceJSON.index"; type="index-pattern" })
    managed = $false
}
$lines += To-Line $savedSearchVirus

# ---- 17. Dashboard ----------------------------------------------
$panels = @(
    # Row 1: 4 metrik (y=0, h=7)
    @{panelIndex="1"; gridData=@{x=0;y=0;w=12;h=7;i="1"};  embeddableConfig=@{}; panelRefName="panel_1"},
    @{panelIndex="2"; gridData=@{x=12;y=0;w=12;h=7;i="2"}; embeddableConfig=@{}; panelRefName="panel_2"},
    @{panelIndex="3"; gridData=@{x=24;y=0;w=12;h=7;i="3"}; embeddableConfig=@{}; panelRefName="panel_3"},
    @{panelIndex="4"; gridData=@{x=36;y=0;w=12;h=7;i="4"}; embeddableConfig=@{}; panelRefName="panel_4"},
    # Row 2: Zaman serisi (y=7, h=12)
    @{panelIndex="5"; gridData=@{x=0;y=7;w=36;h=12;i="5"}; embeddableConfig=@{}; panelRefName="panel_5"},
    # Row 2: Log turu pasta (y=7, h=12)
    @{panelIndex="6"; gridData=@{x=36;y=7;w=12;h=12;i="6"}; embeddableConfig=@{}; panelRefName="panel_6"},
    # Row 3: Top senders/recipients/IPs (y=19, h=12)
    @{panelIndex="7"; gridData=@{x=0;y=19;w=16;h=12;i="7"}; embeddableConfig=@{}; panelRefName="panel_7"},
    @{panelIndex="8"; gridData=@{x=16;y=19;w=16;h=12;i="8"}; embeddableConfig=@{}; panelRefName="panel_8"},
    @{panelIndex="9"; gridData=@{x=32;y=19;w=16;h=12;i="9"}; embeddableConfig=@{}; panelRefName="panel_9"},
    # Row 4: Spam checks + Auth fail + Kevent (y=31, h=12)
    @{panelIndex="10"; gridData=@{x=0;y=31;w=16;h=12;i="10"}; embeddableConfig=@{}; panelRefName="panel_10"},
    @{panelIndex="11"; gridData=@{x=16;y=31;w=16;h=12;i="11"}; embeddableConfig=@{}; panelRefName="panel_11"},
    @{panelIndex="12"; gridData=@{x=32;y=31;w=16;h=12;i="12"}; embeddableConfig=@{}; panelRefName="panel_12"},
    # Row 5: Saved searches (y=43)
    @{panelIndex="13"; gridData=@{x=0;y=43;w=48;h=14;i="13"}; embeddableConfig=@{}; panelRefName="panel_13"},
    @{panelIndex="14"; gridData=@{x=0;y=57;w=48;h=14;i="14"}; embeddableConfig=@{}; panelRefName="panel_14"},
    @{panelIndex="15"; gridData=@{x=0;y=71;w=48;h=14;i="15"}; embeddableConfig=@{}; panelRefName="panel_15"}
)

$references = @(
    [ordered]@{id="fm-viz-total-count";  name="panel_1";  type="visualization"},
    [ordered]@{id="fm-viz-spam-count";   name="panel_2";  type="visualization"},
    [ordered]@{id="fm-viz-virus-count";  name="panel_3";  type="visualization"},
    [ordered]@{id="fm-viz-event-count";  name="panel_4";  type="visualization"},
    [ordered]@{id="fm-viz-traffic-time"; name="panel_5";  type="visualization"},
    [ordered]@{id="fm-viz-logtype-pie";  name="panel_6";  type="visualization"},
    [ordered]@{id="fm-viz-top-senders";  name="panel_7";  type="visualization"},
    [ordered]@{id="fm-viz-top-recipients"; name="panel_8"; type="visualization"},
    [ordered]@{id="fm-viz-top-client-ip"; name="panel_9"; type="visualization"},
    [ordered]@{id="fm-viz-spam-checks";  name="panel_10"; type="visualization"},
    [ordered]@{id="fm-viz-auth-fail";    name="panel_11"; type="visualization"},
    [ordered]@{id="fm-viz-kevent-users"; name="panel_12"; type="visualization"},
    [ordered]@{id="fm-saved-search";     name="panel_13"; type="search"},
    [ordered]@{id="fm-saved-search-spam";  name="panel_14"; type="search"},
    [ordered]@{id="fm-saved-search-virus"; name="panel_15"; type="search"}
)

$dashboard = [ordered]@{
    id   = "fm-dashboard"
    type = "dashboard"
    attributes = [ordered]@{
        title           = "FortiMail - Ana Dashboard"
        description     = "FortiMail syslog analizi: spam, virus, SMTP events, admin degisiklikleri"
        panelsJSON      = ($panels | ConvertTo-Json -Depth 10 -Compress)
        optionsJSON     = "{`"useMargins`":true,`"syncColors`":false,`"hidePanelTitles`":false}"
        uiStateJSON     = "{}"
        timeRestore     = $false
        kibanaSavedObjectMeta = [ordered]@{
            searchSourceJSON = "{`"query`":{`"query`":`"`",`"language`":`"kuery`"},`"filter`":[]}"
        }
    }
    references = $references
    managed = $false
}
$lines += To-Line $dashboard

# ---- Dosyaya yaz ------------------------------------------------
$lines | Set-Content -Path $outFile -Encoding UTF8
Write-Host "Done: $outFile ($($lines.Count) satir)"
