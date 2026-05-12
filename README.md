# AI動画クリエイター インストーラー

[joshicrea/joshicrea-video-creator](https://github.com/joshicrea/joshicrea-video-creator)（PRIVATE）の購入者向けインストーラー。

このリポジトリ自体はPUBLICで、`install.ps1` と `install.sh` だけが置かれています。実際のプラグイン本体はPRIVATEリポジトリにあり、GitHub Personal Access Token (PAT) を使ってダウンロードします。

---

## 購入者の方へ

ご購入ありがとうございます。林からお送りした「アクセストークン」を使ってインストールします。

### Windows の方

Claude Code のチャットに以下を貼り付けて送信してください（`ghp_xxxxx...` の部分は林からお伝えした文字列に置き換え）:

```
以下のURLからAI動画クリエイターのインストーラーを取得して実行してください。
実行前に環境変数 GITHUB_PAT に以下のトークンを設定してください: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.ps1
```

### Mac の方

ターミナル.app を開いて以下を実行（`ghp_xxxxx...` の部分は置き換え）:

```bash
GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  curl -fsSL https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh | bash
```

### インストール後

1. Claude Code を完全に閉じる
2. もう一度開く
3. チャットに「こんにちは」と送信すると、セットアップウィザードが起動します

---

## 販売者の方へ（林さん向け）

### 購入者が出るたびにやること

1. GitHubで Personal Access Token を発行
   - https://github.com/settings/tokens/new
   - Note: `購入者名_video_creator`（誰用か分かる名前にする）
   - Expiration: 1年 or 「期限なし」
   - Scopes: **`repo` 権限のみチェック**
   - 「Generate token」 → 表示されたトークン（`ghp_...`）をコピー

2. 購入者にメール送信
   - 「アクセストークン: ghp_xxxxxxxx」と Windows/Mac 用の貼り付け文を添える

### 購入者が退会・返金時のアクセス取り消し

1. https://github.com/settings/tokens を開く
2. 該当トークン（Note名で識別）を「Revoke」

これで以降のインストール・アップデートはブロックされる。すでにインストール済みのファイルはローカルに残るが、次回アップデート時にダウンロードできなくなる。

### 本体リポジトリの更新を反映する流れ

1. 本体（PRIVATE）を更新してpush
2. 購入者は何もしなくてOK（アップデート時に自動で最新コミットを取得）
3. アップデートを促す場合は「Claude Code チャットで『アップデートして』と話しかけてください」と案内

---

## 仕組みの概要

```
購入者のClaude Code
    ↓ チャット貼り付け
install.ps1 / install.sh （このリポジトリ・PUBLIC）
    ↓ PAT付きでGitHub APIを叩く
joshicrea-video-creator のzipball （PRIVATE本体）
    ↓ ダウンロード・展開
~/.claude/plugins/cache/joshicrea/joshicrea-video-creator/{sha}/
    ↓ Claude Code が認識
プラグインとして動作開始
```

PATは Claude Code チャットで `$env:GITHUB_PAT = "ghp_xxx"` の形で渡され、`install.ps1` 内部で使われたあと `$env:GITHUB_PAT = $null` で破棄されます（再利用はされません）。
