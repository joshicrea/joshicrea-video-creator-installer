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
#   3. ZIPをダウンロードして展開・プラグインキャッシュにコピー
#   4. installed_plugins.json / settings.json を更新
#   5. 全依存関係を自動インストール（winget + pip + npm）
#      - ffmpeg / Node.js LTS / Python（無ければ winget で）
#      - fish-audio-sdk / openai-whisper / google-api-python-client（pip）
#      - Remotion + 関連パッケージ（npm install）
#   6. インストール失敗時は詳細ログを出力

$ErrorActionPreference = "Continue"  # 一部失敗してもインストールを続行
$ProgressPreference = "SilentlyContinue"

Write-Host ""
Write-Host "AI動画クリエイター プラグインをインストールしています..." -ForegroundColor Cyan
Write-Host ""

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# 環境変数 PATH を再読み込み（winget でインストール直後に新コマンドを認識させる）
function Update-EnvPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# --- PAT 取得 ---
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
$LogDir     = [IO.Path]::Combine($ClaudeDir, "logs")
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# ============================================================
# Section 1: 本体プラグインをダウンロード・展開
# ============================================================
Write-Host "[1/5] プラグイン本体をダウンロード..." -ForegroundColor Cyan

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

if (Test-Path $InstallPath) {
    Write-Host "  すでに最新版がダウンロード済み ($ShortSha)" -ForegroundColor Green
} else {
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
    $ExtractedFolder = Get-ChildItem $ExtTemp -Directory | Select-Object -First 1
    Move-Item $ExtractedFolder.FullName $InstallPath -Force
    Remove-Item $ExtTemp -Force -ErrorAction SilentlyContinue
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Write-Host "  ダウンロード完了 ($ShortSha)" -ForegroundColor Green
}

# ============================================================
# Section 2: Claude Code にプラグイン登録
# ============================================================
Write-Host ""
Write-Host "[2/5] Claude Code にプラグイン登録..." -ForegroundColor Cyan

$InstalledPath = [IO.Path]::Combine($PluginsDir, "installed_plugins.json")
if (Test-Path $InstalledPath) {
    $Installed = [System.IO.File]::ReadAllText($InstalledPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
    $Installed = [PSCustomObject]@{ version = 2; plugins = [PSCustomObject]@{} }
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
Write-Host "  プラグイン登録完了" -ForegroundColor Green

# ============================================================
# Section 3: システム依存（winget で自動インストール）
# ============================================================
Write-Host ""
Write-Host "[3/5] システム依存関係を自動インストール..." -ForegroundColor Cyan

$HasWinget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $HasWinget) {
    Write-Host "  警告: winget が見つかりません。Windows 11 標準ですが、Windows 10 ではMicrosoft Storeから「アプリ インストーラー」を入れてください。" -ForegroundColor Yellow
    Write-Host "  https://www.microsoft.com/p/app-installer/9nblggh4nns1"
}

function Install-WithWinget($name, $id) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        if ($HasWinget) {
            Write-Host "  $name をインストール中... (winget id: $id)" -ForegroundColor Gray
            winget install -e --id $id --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
            Update-EnvPath
            if (Get-Command $name -ErrorAction SilentlyContinue) {
                Write-Host "  [OK] $name インストール完了" -ForegroundColor Green
                return $true
            } else {
                Write-Host "  [WARN] $name のインストールに失敗しました。手動で入れてください。" -ForegroundColor Yellow
                return $false
            }
        } else {
            Write-Host "  [SKIP] winget無しのため $name は手動インストールが必要です。" -ForegroundColor Yellow
            return $false
        }
    } else {
        Write-Host "  [OK] $name はインストール済み" -ForegroundColor Green
        return $true
    }
}

$pyOk   = Install-WithWinget "python"  "Python.Python.3.12"
$null   = Install-WithWinget "ffmpeg"  "Gyan.FFmpeg"
$nodeOk = Install-WithWinget "node"    "OpenJS.NodeJS.LTS"

# ============================================================
# Section 4: Pythonパッケージ
# ============================================================
Write-Host ""
Write-Host "[4/5] Pythonパッケージをインストール..." -ForegroundColor Cyan

if ($pyOk) {
    $PipLog = Join-Path $LogDir "pip-install.log"
    Write-Host "  pip 更新中..." -ForegroundColor Gray
    python -m pip install --upgrade pip 2>&1 | Out-File -Append -Encoding utf8 $PipLog

    $pyPackages = @(
        "fish-audio-sdk",
        "openai-whisper",
        "google-api-python-client",
        "google-auth-oauthlib",
        "pyyaml",
        "requests"
    )
    foreach ($pkg in $pyPackages) {
        Write-Host "  $pkg をインストール中..." -ForegroundColor Gray
        python -m pip install --upgrade $pkg 2>&1 | Out-File -Append -Encoding utf8 $PipLog
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] $pkg" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] $pkg のインストールに失敗。ログ: $PipLog" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  [SKIP] Python未インストールのためPythonパッケージはスキップ" -ForegroundColor Yellow
}

# ============================================================
# Section 5: Remotion (npm install)
# ============================================================
Write-Host ""
Write-Host "[5/5] Remotion（テロップ焼き込みエンジン）をインストール..." -ForegroundColor Cyan
Write-Host "  ※ 5〜15分かかる場合があります。途中で止めずにお待ちください。" -ForegroundColor Gray

if ($nodeOk) {
    $RemotionDir = Join-Path $InstallPath "scripts\remotion-project"
    if (-not (Test-Path $RemotionDir)) {
        Write-Host "  [WARN] remotion-project ディレクトリが見つかりません: $RemotionDir" -ForegroundColor Yellow
    } else {
        $NpmLog = Join-Path $LogDir "npm-install.log"
        Push-Location $RemotionDir
        try {
            # package-lock.json と node_modules を削除（EBADPLATFORM対策）
            # GitHubから取得したzipには配布元OS（Linux）の lockfile が含まれることがあり、
            # Windowsで `npm install` するとネイティブバイナリ参照が衝突して失敗する
            $lockFile = Join-Path $RemotionDir "package-lock.json"
            if (Test-Path $lockFile) {
                Write-Host "  既存の package-lock.json を削除（クロスプラットフォーム対応）..." -ForegroundColor Gray
                Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            }
            $nmDir = Join-Path $RemotionDir "node_modules"
            if (Test-Path $nmDir) {
                Remove-Item $nmDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            Write-Host "  npm キャッシュをクリーン..." -ForegroundColor Gray
            npm cache verify 2>&1 | Out-File -Append -Encoding utf8 $NpmLog

            Write-Host "  npm install 実行中..." -ForegroundColor Gray
            npm install --no-audit --no-fund 2>&1 | Out-File -Append -Encoding utf8 $NpmLog

            if (Test-Path (Join-Path $RemotionDir "node_modules\remotion")) {
                Write-Host "  [OK] Remotion インストール完了" -ForegroundColor Green
            } else {
                Write-Host "  [WARN] Remotion のインストールに失敗しました。" -ForegroundColor Yellow
                Write-Host "  詳細ログ: $NpmLog" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  対処方法:" -ForegroundColor Yellow
                Write-Host "    1. PowerShell を管理者として開いて、もう一度ワンライナーを実行" -ForegroundColor Gray
                Write-Host "    2. それでも失敗するなら、以下のフォルダで手動実行:" -ForegroundColor Gray
                Write-Host "       cd `"$RemotionDir`"" -ForegroundColor Gray
                Write-Host "       npm install" -ForegroundColor Gray
                Write-Host "    3. ログ ($NpmLog) を林にお送りください" -ForegroundColor Gray
            }
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Host "  [SKIP] Node.js未インストールのためRemotionはスキップ" -ForegroundColor Yellow
}

# ============================================================
# 完了
# ============================================================
Write-Host ""
Write-Host "=========================================="
Write-Host "インストール完了！" -ForegroundColor Green
Write-Host ""
Write-Host "次の手順:"
Write-Host "  1. Claude Code を完全に閉じる"
Write-Host "  2. Claude Code を再度開く"
Write-Host "  3. チャットに「こんにちは」と送るとセットアップが始まります"
Write-Host ""
if (-not $ffmpegOk -or -not $nodeOk -or -not $pyOk) {
    Write-Host "一部の依存関係が自動インストールできませんでした。" -ForegroundColor Yellow
    Write-Host "Claude Code 起動後に「依存関係を確認して」と話しかけると、不足分の対処を案内します。" -ForegroundColor Yellow
    Write-Host ""
}

# PATを環境変数から消去
$env:GITHUB_PAT = $null
