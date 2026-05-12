# AI動画クリエイター ワンライナーインストーラー (Windows)
#
# 使い方（購入者がClaude Codeチャットに貼り付け）:
#
#   以下のURLからAI動画クリエイターのインストーラーを取得して実行してください。
#   実行前に環境変数 GITHUB_PAT に以下のトークンを設定してください: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
#   https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.ps1
#
# やること:
#   1. GitHub Personal Access Token (PAT) を環境変数から取得
#   2. PRIVATE リポジトリから最新コミットを取得
#   3. ZIPをダウンロードして展開
#   4. プラグインキャッシュにコピー
#   5. installed_plugins.json / settings.json を更新
#   6. 依存関係をチェック

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "AI動画クリエイター プラグインをインストールしています..." -ForegroundColor Cyan
Write-Host ""

# UTF-8 BOMなしファイル書き込み
function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# --- PAT を取得 ---
$Pat = $env:GITHUB_PAT
if (-not $Pat) {
    Write-Host "エラー: GitHub Personal Access Token が設定されていません。" -ForegroundColor Red
    Write-Host ""
    Write-Host "Claude Code のチャットに以下のように貼り付けて再実行してください:"
    Write-Host ""
    Write-Host "  以下のURLからAI動画クリエイターのインストーラーを取得して実行してください。"
    Write-Host "  実行前に環境変数 GITHUB_PAT に購入時にお伝えしたトークンを設定してください。"
    Write-Host "  https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.ps1"
    Write-Host ""
    exit 1
}

# --- OS判定・パス設定 ---
if ($IsWindows -or ($PSVersionTable.PSVersion.Major -lt 6)) {
    $HomeDir = $env:USERPROFILE
} else {
    $HomeDir = $env:HOME
}

$TempDir    = [IO.Path]::GetTempPath()
$ClaudeDir  = [IO.Path]::Combine($HomeDir, ".claude")
$PluginsDir = [IO.Path]::Combine($ClaudeDir, "plugins")
$CacheDir   = [IO.Path]::Combine($PluginsDir, "cache", "joshicrea", "joshicrea-video-creator")

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

# --- GitHubから最新コミット情報を取得（認証ヘッダ付き）---
$Headers = @{
    "Authorization" = "token $Pat"
    "User-Agent"    = "joshicrea-video-creator-installer"
    "Accept"        = "application/vnd.github.v3+json"
}

try {
    $CommitInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/joshicrea/joshicrea-video-creator/commits/master" -Headers $Headers -UseBasicParsing
    $FullSha = $CommitInfo.sha
    $ShortSha = $FullSha.Substring(0, 12)
} catch {
    Write-Host "GitHubへの接続に失敗しました: $_" -ForegroundColor Red
    Write-Host "Personal Access Token が正しいか、リポジトリへのアクセス権があるか確認してください。"
    exit 1
}

$InstallPath = [IO.Path]::Combine($CacheDir, $ShortSha)

# すでにインストール済みかチェック
if (Test-Path $InstallPath) {
    Write-Host "すでに最新版がインストールされています ($ShortSha)" -ForegroundColor Green
} else {
    # --- ZIPをダウンロード（認証ヘッダ付き）---
    $ZipUrl  = "https://api.github.com/repos/joshicrea/joshicrea-video-creator/zipball/master"
    $ZipPath = [IO.Path]::Combine($TempDir, "joshicrea-video-creator.zip")
    $ExtTemp = [IO.Path]::Combine($TempDir, "joshicrea-vc-extract-$ShortSha")

    try {
        Invoke-WebRequest -Uri $ZipUrl -Headers $Headers -OutFile $ZipPath -UseBasicParsing
    } catch {
        Write-Host "ダウンロードに失敗しました: $_" -ForegroundColor Red
        exit 1
    }

    if (Test-Path $ExtTemp) { Remove-Item $ExtTemp -Recurse -Force }
    Expand-Archive -Path $ZipPath -DestinationPath $ExtTemp -Force

    # GitHub API のzipballは "joshicrea-joshicrea-video-creator-{sha7}/" フォルダに展開される
    $ExtractedFolder = Get-ChildItem $ExtTemp -Directory | Select-Object -First 1
    Move-Item $ExtractedFolder.FullName $InstallPath -Force
    Remove-Item $ExtTemp -Force -ErrorAction SilentlyContinue
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue

    Write-Host "[OK] ダウンロード完了 ($ShortSha)" -ForegroundColor Green
}

# --- installed_plugins.json を更新 ---
$InstalledPath = [IO.Path]::Combine($PluginsDir, "installed_plugins.json")

if (Test-Path $InstalledPath) {
    $Installed = [System.IO.File]::ReadAllText($InstalledPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
    $Installed = [PSCustomObject]@{
        version = 2
        plugins = [PSCustomObject]@{}
    }
}

$PluginEntry = [PSCustomObject]@{
    scope        = "user"
    installPath  = $InstallPath
    version      = $ShortSha
    installedAt  = (Get-Date -Format "o")
    lastUpdated  = (Get-Date -Format "o")
    gitCommitSha = $FullSha
}

$Key = "joshicrea-video-creator@joshicrea"
if ($Installed.plugins.PSObject.Properties[$Key]) {
    $Installed.plugins.PSObject.Properties[$Key].Value = @($PluginEntry)
} else {
    $Installed.plugins | Add-Member -Name $Key -Value @($PluginEntry) -MemberType NoteProperty
}

Write-Utf8NoBom -Path $InstalledPath -Content ($Installed | ConvertTo-Json -Depth 10)

# --- settings.json に enabledPlugins を追加 ---
$SettingsPath = [IO.Path]::Combine($ClaudeDir, "settings.json")

if (Test-Path $SettingsPath) {
    $Settings = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} else {
    $Settings = [PSCustomObject]@{}
}

if (-not ($Settings.PSObject.Properties["enabledPlugins"])) {
    $Settings | Add-Member -Name "enabledPlugins" -Value ([PSCustomObject]@{}) -MemberType NoteProperty
}

if ($Settings.enabledPlugins.PSObject.Properties[$Key]) {
    $Settings.enabledPlugins.PSObject.Properties[$Key].Value = $true
} else {
    $Settings.enabledPlugins | Add-Member -Name $Key -Value $true -MemberType NoteProperty
}

Write-Utf8NoBom -Path $SettingsPath -Content ($Settings | ConvertTo-Json -Depth 10)

Write-Host "[OK] Claude Code にプラグインを登録" -ForegroundColor Green
Write-Host ""

# --- 依存関係チェック ---
Write-Host "依存関係をチェックしています..." -ForegroundColor Cyan

$Missing = @()
function Check-Tool($name, $cmd, $hint) {
    Write-Host -NoNewline "[$name] "
    try {
        Invoke-Expression $cmd 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "OK" -ForegroundColor Green
            return $true
        }
    } catch {}
    Write-Host "未インストール" -ForegroundColor Yellow
    Write-Host "  → $hint" -ForegroundColor Gray
    return $false
}

if (-not (Check-Tool "Python 3.10+" "python --version" "https://www.python.org/downloads/")) { $Missing += "Python" }
if (-not (Check-Tool "ffmpeg" "ffmpeg -version" "winget install ffmpeg")) { $Missing += "ffmpeg" }
if (-not (Check-Tool "Node.js 18+" "node --version" "https://nodejs.org/")) { $Missing += "Node.js" }

Write-Host ""
Write-Host "Pythonパッケージ:" -ForegroundColor Cyan
Write-Host -NoNewline "[fish-audio-sdk] "
if (pip show fish-audio-sdk 2>$null) {
    Write-Host "OK" -ForegroundColor Green
} else {
    Write-Host "未インストール" -ForegroundColor Yellow
    Write-Host "  → pip install fish-audio-sdk" -ForegroundColor Gray
    $Missing += "fish-audio-sdk"
}

Write-Host -NoNewline "[google-api-python-client] "
if (pip show google-api-python-client 2>$null) {
    Write-Host "OK" -ForegroundColor Green
} else {
    Write-Host "未インストール" -ForegroundColor Yellow
    Write-Host "  → pip install google-api-python-client google-auth-oauthlib pyyaml requests" -ForegroundColor Gray
    $Missing += "google-api-python-client"
}

Write-Host ""
Write-Host "Remotion (Node.js):" -ForegroundColor Cyan
$RemotionDir = Join-Path $InstallPath "scripts\remotion-project"
if (Test-Path (Join-Path $RemotionDir "node_modules\remotion")) {
    Write-Host "[remotion] OK" -ForegroundColor Green
} else {
    Write-Host "[remotion] 未インストール" -ForegroundColor Yellow
    Write-Host "  → cd `"$RemotionDir`" ; npm install" -ForegroundColor Gray
    $Missing += "remotion"
}

Write-Host ""
Write-Host "=========================================="
if ($Missing.Count -eq 0) {
    Write-Host "インストール完了！" -ForegroundColor Green
    Write-Host ""
    Write-Host "次の手順:"
    Write-Host "  1. Claude Code を完全に閉じる"
    Write-Host "  2. Claude Code を再度開く"
    Write-Host "  3. チャットに「こんにちは」と送るとセットアップが始まります"
} else {
    Write-Host "プラグインの登録は完了しました。" -ForegroundColor Green
    Write-Host "次の依存関係が未インストールです:" -ForegroundColor Yellow
    Write-Host "  $($Missing -join ', ')"
    Write-Host ""
    Write-Host "上記の手順でインストールしてから Claude Code を再起動してください。"
}
Write-Host ""

# 念のためPATを環境変数から消去（セキュリティ）
$env:GITHUB_PAT = $null
