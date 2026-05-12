#!/usr/bin/env bash
# AI動画クリエイター ワンライナーインストーラー (Mac/Linux)
#
# 使い方:
#   GITHUB_PAT=ghp_xxxx curl -fsSL https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh | bash

set -e

echo ""
echo "AI動画クリエイター プラグインをインストールしています..."
echo ""

# --- PAT を取得 ---
if [ -z "$GITHUB_PAT" ]; then
    echo "エラー: GitHub Personal Access Token が設定されていません。"
    echo ""
    echo "ターミナルに以下のように貼り付けて再実行してください:"
    echo "  GITHUB_PAT=ghp_xxxxxxxx curl -fsSL https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh | bash"
    exit 1
fi

HOME_DIR="$HOME"
TEMP_DIR="${TMPDIR:-/tmp}"
CLAUDE_DIR="$HOME_DIR/.claude"
PLUGINS_DIR="$CLAUDE_DIR/plugins"
CACHE_DIR="$PLUGINS_DIR/cache/joshicrea/joshicrea-video-creator"

mkdir -p "$CACHE_DIR"

# --- 最新コミットSHAを取得 ---
COMMIT_JSON=$(curl -fsSL \
    -H "Authorization: token $GITHUB_PAT" \
    -H "User-Agent: joshicrea-video-creator-installer" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/joshicrea/joshicrea-video-creator/commits/master") || {
    echo "GitHubへの接続に失敗しました。"
    echo "Personal Access Token が正しいか、リポジトリへのアクセス権があるか確認してください。"
    exit 1
}

FULL_SHA=$(echo "$COMMIT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)['sha'])")
SHORT_SHA="${FULL_SHA:0:12}"
INSTALL_PATH="$CACHE_DIR/$SHORT_SHA"

if [ -d "$INSTALL_PATH" ]; then
    echo "すでに最新版がインストールされています ($SHORT_SHA)"
else
    # --- ZIPダウンロード ---
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

    echo "[OK] ダウンロード完了 ($SHORT_SHA)"
fi

# --- installed_plugins.json を更新 ---
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

# --- settings.json に enabledPlugins を追加 ---
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

echo "[OK] Claude Code にプラグインを登録"
echo ""
echo "依存関係をチェックしています..."

missing=()
check_tool() {
    local name="$1"; local cmd="$2"; local hint="$3"
    printf "[%s] " "$name"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "OK"
    else
        echo "未インストール"
        echo "  → $hint"
        missing+=("$name")
    fi
}

check_tool "Python 3.10+" "python3 --version" "Mac: brew install python / Linux: apt install python3"
check_tool "ffmpeg" "ffmpeg -version" "Mac: brew install ffmpeg / Linux: apt install ffmpeg"
check_tool "Node.js 18+" "node --version" "https://nodejs.org/"

echo ""
echo "Pythonパッケージ:"
printf "[fish-audio-sdk] "
if pip3 show fish-audio-sdk >/dev/null 2>&1; then echo "OK"
else
    echo "未インストール"
    echo "  → pip3 install fish-audio-sdk"
    missing+=("fish-audio-sdk")
fi

printf "[google-api-python-client] "
if pip3 show google-api-python-client >/dev/null 2>&1; then echo "OK"
else
    echo "未インストール"
    echo "  → pip3 install google-api-python-client google-auth-oauthlib pyyaml requests"
    missing+=("google-api-python-client")
fi

echo ""
echo "Remotion (Node.js):"
REMOTION_DIR="$INSTALL_PATH/scripts/remotion-project"
if [ -d "$REMOTION_DIR/node_modules/remotion" ]; then
    echo "[remotion] OK"
else
    echo "[remotion] 未インストール"
    echo "  → cd \"$REMOTION_DIR\" && npm install"
    missing+=("remotion")
fi

echo ""
echo "=========================================="
if [ ${#missing[@]} -eq 0 ]; then
    echo "インストール完了！"
    echo ""
    echo "次の手順:"
    echo "  1. Claude Code を完全に閉じる"
    echo "  2. Claude Code を再度開く"
    echo "  3. チャットに「こんにちは」と送るとセットアップが始まります"
else
    echo "プラグインの登録は完了しました。"
    echo "次の依存関係が未インストールです:"
    echo "  ${missing[*]}"
    echo ""
    echo "上記の手順でインストールしてから Claude Code を再起動してください。"
fi
echo ""

# 念のためPATをアンセット
unset GITHUB_PAT
