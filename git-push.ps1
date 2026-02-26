# ================================================================
# ExchangeELK - GitHub'a ilk yükleme scripti
# VS Code yeniden başlatıldıktan sonra bu scripti çalıştırın.
#
# Kullanım:
#   .\git-push.ps1 -GithubUser "kullaniciadi" -RepoName "ExchangeELK"
#
# Öncesinde GitHub'da boş bir repo oluşturun:
#   1. github.com → New Repository
#   2. Ad: ExchangeELK
#   3. Açıklama: Exchange Server DAG ELK Stack
#   4. Private veya Public seçin
#   5. README / .gitignore / license eklemeyin (zaten mevcut)
#   6. "Create Repository" tıklayın
# ================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$GithubUser,

    [Parameter(Mandatory=$false)]
    [string]$RepoName = "ExchangeELK",

    [Parameter(Mandatory=$false)]
    [string]$Branch = "main"
)

$RepoPath = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "`n=== ExchangeELK GitHub Push ===" -ForegroundColor Cyan
Write-Host "Hedef: https://github.com/$GithubUser/$RepoName" -ForegroundColor Yellow

Set-Location $RepoPath

# Git identity (ilk kez kuruluysa)
$gitEmail = git config --global user.email 2>$null
if (-not $gitEmail) {
    $email = Read-Host "Git email adresinizi girin"
    $name  = Read-Host "Git adınızı girin"
    git config --global user.email "$email"
    git config --global user.name  "$name"
}

# Init
if (-not (Test-Path ".git")) {
    Write-Host "`nGit repo başlatılıyor..." -ForegroundColor Green
    git init
    git checkout -b $Branch 2>$null
} else {
    Write-Host "`nGit repo zaten mevcut." -ForegroundColor Green
    git checkout -b $Branch 2>$null
}

# Remote ekle
$remoteUrl = "https://github.com/$GithubUser/$RepoName.git"
$existingRemote = git remote 2>$null
if ($existingRemote -contains "origin") {
    Write-Host "Remote 'origin' güncelleniyor: $remoteUrl" -ForegroundColor Yellow
    git remote set-url origin $remoteUrl
} else {
    Write-Host "Remote ekleniyor: $remoteUrl" -ForegroundColor Green
    git remote add origin $remoteUrl
}

# Tüm dosyaları stage et
Write-Host "`nDosyalar stage ediliyor..." -ForegroundColor Green
git add --all

# Durum göster
Write-Host "`nGit status:" -ForegroundColor Cyan
git status --short

# Commit
Write-Host "`nCommit oluşturuluyor..." -ForegroundColor Green
git commit -m "feat: Exchange ELK Stack - P2P pipeline mimarisi, ILM, 2. disk desteği

- Pipeline-to-Pipeline (P2P) mimarisi: router + 4 downstream pipeline
- MessageTracking CSV 30 sütun parse, GeoIP, Europe/Istanbul TZ
- IIS W3C + X-Forwarded-For (OrgclientIP) desteği
- HttpProxy (77 sütun) ve MapiHttp (47 sütun) ayrı parse
- SMTP Receive + Send parse, GeoIP
- Tüm veriler 2. diske (/data) yazılır, sistem diski şişmez
- ILM: Hot 7g → Warm 30g (best_compression) → Cold 90g (freeze) → Delete
- Persistent Queue 4 GB + Dead Letter Queue 1 GB
- SLM: Her gece 02:30 otomatik snapshot, 30 gün saklama
- 6 Filebeat input, tek port (5044), tag bazlı yönlendirme
- ELK 8.11.1 | Ubuntu 22.04 | Docker Compose"

# Push
Write-Host "`nGitHub'a push yapılıyor..." -ForegroundColor Green
Write-Host "(GitHub kullanıcı adı ve token/şifre istenebilir)" -ForegroundColor Yellow
git push -u origin $Branch

Write-Host "`n=== TAMAMLANDI ===" -ForegroundColor Green
Write-Host "Repo URL: https://github.com/$GithubUser/$RepoName" -ForegroundColor Cyan
