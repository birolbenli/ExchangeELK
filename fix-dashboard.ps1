$file    = 'C:\Github\ExchangeELK\dashboards\fortimail-dashboard.ndjson'
$enc     = [System.Text.UTF8Encoding]::new($false)

# Read helper files that contain exact old strings (extracted earlier)
$oldPanels = [System.IO.File]::ReadAllText('C:\Github\ExchangeELK\old_panels.txt', [System.Text.Encoding]::UTF8)
$oldAgg3   = [System.IO.File]::ReadAllText('C:\Github\ExchangeELK\old_agg3.txt',   [System.Text.Encoding]::UTF8)

# New panels JSON (escaped for JSON-in-JSON, h:7 for metrics, larger for viz panels)
$newPanels = '[{\"panelIndex\":\"1\",\"gridData\":{\"x\":0,\"y\":0,\"w\":10,\"h\":7,\"i\":\"1\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_1\"},{\"panelIndex\":\"2\",\"gridData\":{\"x\":10,\"y\":0,\"w\":10,\"h\":7,\"i\":\"2\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_2\"},{\"panelIndex\":\"3\",\"gridData\":{\"x\":20,\"y\":0,\"w\":10,\"h\":7,\"i\":\"3\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_3\"},{\"panelIndex\":\"4\",\"gridData\":{\"x\":30,\"y\":0,\"w\":9,\"h\":7,\"i\":\"4\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_4\"},{\"panelIndex\":\"5\",\"gridData\":{\"x\":39,\"y\":0,\"w\":9,\"h\":7,\"i\":\"5\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_5\"},{\"panelIndex\":\"6\",\"gridData\":{\"x\":0,\"y\":7,\"w\":48,\"h\":10,\"i\":\"6\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_6\"},{\"panelIndex\":\"7\",\"gridData\":{\"x\":0,\"y\":17,\"w\":48,\"h\":16,\"i\":\"7\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_7\"},{\"panelIndex\":\"8\",\"gridData\":{\"x\":0,\"y\":33,\"w\":12,\"h\":16,\"i\":\"8\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_8\"},{\"panelIndex\":\"9\",\"gridData\":{\"x\":12,\"y\":33,\"w\":12,\"h\":16,\"i\":\"9\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_9\"},{\"panelIndex\":\"10\",\"gridData\":{\"x\":24,\"y\":33,\"w\":12,\"h\":16,\"i\":\"10\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_10\"},{\"panelIndex\":\"11\",\"gridData\":{\"x\":36,\"y\":33,\"w\":12,\"h\":16,\"i\":\"11\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_11\"},{\"panelIndex\":\"12\",\"gridData\":{\"x\":0,\"y\":49,\"w\":16,\"h\":18,\"i\":\"12\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_12\"},{\"panelIndex\":\"13\",\"gridData\":{\"x\":16,\"y\":49,\"w\":16,\"h\":18,\"i\":\"13\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_13\"},{\"panelIndex\":\"14\",\"gridData\":{\"x\":32,\"y\":49,\"w\":16,\"h\":18,\"i\":\"14\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_14\"},{\"panelIndex\":\"15\",\"gridData\":{\"x\":0,\"y\":67,\"w\":24,\"h\":18,\"i\":\"15\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_15\"},{\"panelIndex\":\"16\",\"gridData\":{\"x\":24,\"y\":67,\"w\":24,\"h\":18,\"i\":\"16\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_16\"},{\"panelIndex\":\"17\",\"gridData\":{\"x\":0,\"y\":85,\"w\":48,\"h\":18,\"i\":\"17\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_17\"},{\"panelIndex\":\"18\",\"gridData\":{\"x\":0,\"y\":103,\"w\":48,\"h\":22,\"i\":\"18\"},\"embeddableConfig\":{},\"panelRefName\":\"panel_18\"}]'

# New agg3: terms on log_type (replaces filters agg that causes Kibana 8 "layered" error)
$newAgg3 = '\"id\":\"3\",\"enabled\":true,\"type\":\"terms\",\"params\":{\"field\":\"log_type\",\"size\":6,\"order\":\"desc\",\"orderBy\":\"1\",\"otherBucket\":false,\"missingBucket\":false},\"schema\":\"group\"}'

# ---- Read and apply all fixes ----
$content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)

# Fix 1: font size 36->60 (literal replace, no regex)
$before1 = $content.Contains('fontSize\":36')
$content = $content.Replace('fontSize\":36', 'fontSize\":60')
Write-Host "Fix1 (fontSize 36->60): was_present=$before1"

# Fix 2: traffic chart agg filters->terms (literal replace)
$before2 = $content.Contains($oldAgg3)
$content = $content.Replace($oldAgg3, $newAgg3)
Write-Host "Fix2 (traffic chart agg): was_present=$before2"

# Fix 3: dashboard panels (literal replace)
$before3 = $content.Contains($oldPanels)
$content = $content.Replace($oldPanels, $newPanels)
Write-Host "Fix3 (dashboard panels): was_present=$before3"

[System.IO.File]::WriteAllText($file, $content, $enc)

# Verify
$verify = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
$lines  = ($verify -split "`n" | Where-Object { $_.Trim() -ne '' }).Count
$fs36   = $verify.Contains('fontSize\":36')
$fs60   = ([regex]::Matches($verify, 'fontSize\\\":\d+')).Count
$panOK  = $verify.Contains($newPanels)
$agg3OK = $verify.Contains($newAgg3)
Write-Host "Lines: $lines | fontSize36_remains: $fs36 | fontSize60_count: $fs60 | panels_new: $panOK | agg3_terms: $agg3OK"
