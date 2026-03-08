$enc = New-Object System.Text.UTF8Encoding($false)
$path = "c:\Github\ExchangeELK\dashboards\exchange-main-dashboard.ndjson"
$lines = [System.IO.File]::ReadAllLines($path, $enc)
Write-Host "Total lines: $($lines.Count)"

$changed = $false
for ($i = 0; $i -lt $lines.Count; $i++) {
    $obj = $lines[$i] | ConvertFrom-Json
    if ($obj.type -eq "index-pattern") {
        $f = $obj.attributes.fields
        if ($f -and $f.Length -gt 0) {
            $first = $f.Substring(0,1)
            Write-Host "Line $i : id=$($obj.id) fields_start=[$first]"
            if ($first -eq "{") {
                # Parse approach: get exact escaped representation from ConvertTo-Json
                # then replace in raw line to avoid re-serializing the whole object
                $escapedOld = ($f | ConvertTo-Json -Compress)      # "\"...\"" with outer quotes
                $escapedNew = (("[" + $f + "]") | ConvertTo-Json -Compress)
                $searchStr  = '"fields":' + $escapedOld
                $replaceStr = '"fields":' + $escapedNew
                $rawLine    = $lines[$i]
                if ($rawLine.Contains($searchStr)) {
                    $lines[$i] = $rawLine.Replace($searchStr, $replaceStr)
                    $changed = $true
                    Write-Host "  -> FIXED line $i"
                } else {
                    Write-Host "  -> Could not find exact string, skipping line $i"
                }
            } elseif ($first -eq "[") {
                Write-Host "  -> Already array, OK"
            } else {
                Write-Host "  -> Unexpected first char: [$first]"
            }
        } else {
            Write-Host "Line $i : id=$($obj.id) fields=EMPTY (OK)"
        }
    }
}

if ($changed) {
    $allValid = $true
    foreach ($line in $lines) {
        try { $null = $line | ConvertFrom-Json }
        catch { $allValid = $false; Write-Host "INVALID JSON detected!" }
    }
    if ($allValid) {
        [System.IO.File]::WriteAllLines($path, $lines, $enc)
        Write-Host "SUCCESS: File written. Lines: $($lines.Count)"
    } else {
        Write-Host "ERROR: Validation failed, NOT written"
    }
} else {
    Write-Host "No changes needed."
}
