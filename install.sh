#!/usr/bin/env bash
# AI動画クリエイター ワンライナーインストーラー (Mac/Linux)
#
# 使い方:
#   GITHUB_PAT=ghp_xxxx curl -fsSL https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh | bash
#
# やること:
#   1. PRIVATEリポジトリから本体をダウンロード・展開
#   2. installed_plugins.json / settings.json を更新
#   3. 全依存関係を自動インストール
#      - Mac: brew install ffmpeg / node / python3
#      - Linux: apt install ffmpeg / nodejs / python3
#      - Python パッケージ（pip）
#      - Remotion（npm install）

set +e  # 一部失敗しても続行

echo ""
echo "AI動画クリエイター プラグインをインストールしています..."
echo ""

# --- PAT 取得 ---
if [ -z "$GITHUB_PAT" ]; then
    echo "エラー: GitHub Personal Access Token が設定されていません。"
    echo ""
    echo "ターミナルに以下のように貼り付けて再実行してください:"
    echo "  GITHUB_PAT=ghp_xxxxxxxx curl -fsSL https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh | bash"
    exit 1
fi

# --- OS判定 ---
case "$(uname -s)" in
    Darwin*) OS="mac";;
    Linux*)  OS="linux";;
    *)       OS="unknown";;
esac

HOME_DIR="$HOME"
TEMP_DIR="${TMPDIR:-/tmp}"
CLAUDE_DIR="$HOME_DIR/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
CACHE_DIR="$PLUGINS_DIR/cache/joshicrea/joshicrea-video-creator"
LOG_DIR="$CLAUDE_DIR/logs"
mkdir -p "$CACHE_DIR" "$LOG_DIR"

# ============================================================
# Section 1: 本体プラグインをダウンロード・展開
# ============================================================
echo "[1/5] プラグイン本体をダウンロード..."

COMMIT_JSON=$(curl -fsSL \
    -H "Authorization: token $GITHUB_PAT" \
    -H "User-Agent: joshicrea-video-creator-installer" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/joshicrea/joshicrea-video-creator/commits/master") || {
    echo "GitHubへの接続に失敗しました。Personal Access Token を確認してください。"
    exit 1
}

FULL_SHA=$(echo "$COMMIT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['sha'])")
SHORT_SHA="${FULL_SHA:0:12}"
INSTALL_PATH="$CACHE_DIR/$SHORT_SHA"

if [ -d "$INSTALL_PATH" ]; then
    echo "  すでに最新版がダウンロード済み ($SHORT_SHA)"
else
    ZIP_URL="https://api.github.com/repos/joshicrea/joshicrea-video-creator/zipball/master"
    ZIP_PATH="$TEMP_DIR/joshicrea-video-creator.zip"
    EXT_TEMP="$TEMP_DIR/joshicrea-vc-extract-$SHORT_SHA"

    curl -fsSL \
        -H "Authorization: token $GITHUB_PAT" \
        -H "User-Agent: joshicrea-video-creator-installer" \
        -o "$ZIP_PATH" "$ZIP_URL" || {
        echo "ダウンロードに失敗しました。"
        exit 1
    }

    rm -rf "$EXT_TEMP"
    mkdir -p "$EXT_TEMP"
    unzip -q "$ZIP_PATH" -d "$EXT_TEMP"
    EXTRACTED=$(ls -d "$EXT_TEMP"/*/ | head -n 1)
    mv "$EXTRACTED" "$INSTALL_PATH"
    rm -rf "$EXT_TEMP" "$ZIP_PATH"
    echo "  ダウンロード完了 ($SHORT_SHA)"
fi

# ============================================================
# Section 2: Claude Code にプラグイン登録
# ============================================================
echo ""
echo "[2/5] Claude Code にプラグイン登録..."

INSTALLED_PATH="$PLUGINS_DIR/installed_plugins.json"
mkdir -p "$PLUGINS_DIR"

KEY="joshicrea-video-creator@joshicrea"
INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 <<PYEOF
import json, os
path = "$INSTALLED_PATH"
key = "$KEY"
entry = {
    "scope": "user",
    "installPath": "$INSTALL_PATH",
    "version": "$SHORT_SHA",
    "installedAt": "$INSTALLED_AT",
    "lastUpdated": "$INSTALLED_AT",
    "gitCommitSha": "$FULL_SHA"
}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {"version": 2, "plugins": {}}
data.setdefault("plugins", {})[key] = [entry]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF

SETTINGS_PATH="$CLAUDE_DIR/settings.json"
python3 <<PYEOF
import json, os
path = "$SETTINGS_PATH"
key = "$KEY"
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}
data.setdefault("enabledPlugins", {})[key] = True
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF

echo "  プラグイン登録完了"

# ============================================================
# Section 3: システム依存（brew/apt で自動インストール）
# ============================================================
echo ""
echo "[3/5] システム依存関係を自動インストール..."

PY_OK=true; FFMPEG_OK=true; NODE_OK=true

install_pkg() {
    local cmd="$1"; local mac_pkg="$2"; local apt_pkg="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  [OK] $cmd インストール済み"
        return 0
    fi
    echo "  $cmd をインストール中..."
    if [ "$OS" = "mac" ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install "$mac_pkg" >/dev/null 2>&1
        else
            echo "  [WARN] Homebrew が無いため $cmd は手動インストールが必要"
            echo "    https://brew.sh/ から brew をインストールしてください"
            return 1
        fi
    elif [ "$OS" = "linux" ]; then
        sudo apt install -y "$apt_pkg" >/dev/null 2>&1
    else
        echo "  [WARN] 未対応OSのため $cmd は手動インストール"
        return 1
    fi
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  [OK] $cmd インストール完了"
        return 0
    else
        echo "  [WARN] $cmd のインストールに失敗"
        return 1
    fi
}

install_pkg "python3" "python" "python3"     || PY_OK=false
install_pkg "ffmpeg"  "ffmpeg" "ffmpeg"      || FFMPEG_OK=false
install_pkg "node"    "node"   "nodejs npm"  || NODE_OK=false

# ============================================================
# Section 4: Pythonパッケージ
# ============================================================
echo ""
echo "[4/5] Pythonパッケージをインストール..."

if $PY_OK; then
    PIP_LOG="$LOG_DIR/pip-install.log"
    echo "  pip 更新中..."
    python3 -m pip install --upgrade pip >> "$PIP_LOG" 2>&1

    for pkg in fish-audio-sdk openai-whisper google-api-python-client google-auth-oauthlib pyyaml requests; do
        echo "  $pkg をインストール中..."
        python3 -m pip install --upgrade "$pkg" >> "$PIP_LOG" 2>&1
        if [ $? -eq 0 ]; then
            echo "  [OK] $pkg"
        else
            echo "  [WARN] $pkg のインストールに失敗。ログ: $PIP_LOG"
        fi
    done
else
    echo "  [SKIP] Python未インストール"
fi

# ============================================================
# Section 5: Remotion (npm install)
# ============================================================
echo ""
echo "[5/5] Remotion（テロップ焼き込みエンジン）をインストール..."
echo "  ※ 5〜15分かかる場合があります。"

if $NODE_OK; then
    REMOTION_DIR="$INSTALL_PATH/scripts/remotion-project"
    if [ ! -d "$REMOTION_DIR" ]; then
        echo "  [WARN] remotion-project ディレクトリが見つかりません"
    else
        NPM_LOG="$LOG_DIR/npm-install.log"
        cd "$REMOTION_DIR"
        # package-lock.json と node_modules を削除（EBADPLATFORM対策）
        # GitHubから取得したzipには配布元OS（Linux）の lockfile が含まれることがあり、
        # 別OSで `npm install` するとネイティブバイナリ参照が衝突して失敗する
        if [ -f package-lock.json ]; then
            echo "  既存の package-lock.json を削除（クロスプラットフォーム対応）..."
            rm -f package-lock.json
        fi
        rm -rf node_modules
        echo "  npm キャッシュをクリーン..."
        npm cache verify >> "$NPM_LOG" 2>&1
        echo "  npm install 実行中..."
        npm install --no-audit --no-fund >> "$NPM_LOG" 2>&1

        if [ -d "$REMOTION_DIR/node_modules/remotion" ]; then
            echo "  [OK] Remotion インストール完了"
        else
            echo "  [WARN] Remotion のインストールに失敗しました。"
            echo "  詳細ログ: $NPM_LOG"
            echo ""
            echo "  対処方法:"
            echo "    1. ターミナルで以下を手動実行:"
            echo "       cd \"$REMOTION_DIR\""
            echo "       npm install"
            echo "    2. ログ ($NPM_LOG) を林にお送りください"
        fi
        cd - >/dev/null
    fi
else
    echo "  [SKIP] Node.js未インストール"
fi

# ============================================================
# 完了
# ============================================================
echo ""
echo "=========================================="
echo "インストール完了！"
echo ""
echo "次の手順:"
echo "  1. Claude Code を完全に閉じる"
echo "  2. Claude Code を再度開く"
echo "  3. チャットに「こんにちは」と送るとセットアップが始まります"
echo ""

unset GITHUB_PAT
