# AI動画クリエイター インストーラー

[joshicrea/joshicrea-video-creator](https://github.com/joshicrea/joshicrea-video-creator)（PRIVATE）の購入者向けインストーラー。

このリポジトリ自体はPUBLICで、`install.ps1` と `install.sh` だけが置かれています。実際のプラグイン本体はPRIVATEリポジトリにあり、GitHub CLI (gh) 経由でダウンロードします。

---

## 購入者の方へ

ご購入ありがとうございます。GitHubの招待を承認してから、以下の手順でインストールしてください。

### Windows の方

Claude Code のチャットに以下をそのまま貼り付けて送信してください:

```
以下のURLからAI動画クリエイターのインストールスクリプトを取得して、内容を確認してから実行してください: https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.ps1
```

### Mac の方

Claude Code のチャットに以下をそのまま貼り付けて送信してください:

```
以下のURLからAI動画クリエイターのインストールスクリプトを取得して、内容を確認してから実行してください: https://raw.githubusercontent.com/joshicrea/joshicrea-video-creator-installer/master/install.sh
```

### インストール後

1. Claude Code を完全に閉じる
2. もう一度開く
3. チャットに「こんにちは」と送信すると、セットアップウィザードが起動します

---

## 販売者の方へ（林さん向け）

### 購入者が出るたびにやること

1. GitHubで購入者のGitHubアカウント（メアド）を `joshicrea/joshicrea-video-creator` のコラボレーターに招待
   - https://github.com/joshicrea/joshicrea-video-creator/settings/access
   - 「Add people」→ 購入者のGitHubメアドを入力 → 「Add collaborator」
   - 購入者に「GitHubから招待メールが届くので承認してください」と案内

2. 購入者は招待メールの「View invitation」→「Accept invitation」で承認するだけ（PAT不要）

### 購入者が退会・返金時のアクセス取り消し

1. https://github.com/joshicrea/joshicrea-video-creator/settings/access を開く
2. 該当ユーザーを「Remove」

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
    ↓ gh auth login --web でGitHub認証
joshicrea-video-creator のzipball （PRIVATE本体）
    ↓ ダウンロード・展開
~/.claude/plugins/cache/joshicrea/joshicrea-video-creator/{sha}/
    ↓ Claude Code が認識
プラグインとして動作開始
```

認証はGitHub CLI (gh) のOAuthフローで行われます。PATの発行・管理・送付は不要です。
