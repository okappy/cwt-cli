# cwt-cli

Claude Worktree launcher - Issue番号からworktree + Claude + Playwrightセッションをグリッドペインで一括起動する Claude Code プラグイン。

## 機能

- **複数issue並列開発**: issue番号を指定するだけで、Windows Terminalにグリッドレイアウトのペインを自動作成
- **Playwrightセッション分離**: 各worktreeに専用のPlaywrightセッションを自動割り当て
- **ワンコマンド**: `cwt 42 43 45` で3つのissueの開発環境を一括起動
- **Claude Code統合**: `/cwt` コマンドでworktree管理をClaude内から実行

## グリッドレイアウト

```
N=1: [cur | A]                    1x2
N=2: [cur | A | B]               1x3
N=3: [cur | A] / [B | C]         2x2
N=4: [cur | A] / [B | C | D]     top2 + bottom3
N=5: [cur | A | B] / [C | D | E] 3x2
```

## 前提条件

- Windows Terminal (`wt.exe`)
- Git Bash (`C:\Program Files\Git\bin\bash.exe`)
- [Claude Code](https://claude.ai/claude-code)
- [playwright-cli](https://github.com/microsoft/playwright-cli) (オプション)
- [git-worktree-runner](https://github.com/coderabbitai/git-worktree-runner) (オプション、`git gtr` コマンド)

## インストール

### プラグインとして使用

```bash
# Claude Code にプラグインとして追加
claude plugin add ~/projects/cwt-cli
```

### スクリプト単体で使用

```bash
# ~/bin にコピー（PATHに ~/bin が含まれている前提）
cp scripts/cwt.sh ~/bin/cwt
chmod +x ~/bin/cwt
```

> **Note**: Windows では `ln -s` による symlink に管理者権限が必要。権限がない場合はコピーで運用。

## 使い方

### ターミナルから（cwt スクリプト）

```bash
# 複数issueの開発環境を一括起動
cwt 42 43 45

# worktree一覧 + Playwrightセッション一覧
cwt list

# worktreeを削除
cwt rm issue-42 issue-43

# 全クリーンアップ（Playwrightセッション + 不要worktree）
cwt clean
```

### Claude Code内から（/cwt コマンド）

```
/cwt list          - worktree一覧
/cwt new 42        - issue #42 のworktree作成
/cwt rm issue-42   - worktree削除
/cwt clean         - クリーンアップ
/cwt session       - 現在のPlaywrightセッション名
```

## プラグイン構成

```
cwt-cli/
├── .claude-plugin/
│   └── plugin.json          # プラグインマニフェスト
├── commands/
│   └── cwt.md               # /cwt コマンド定義
├── rules/
│   └── playwright-cli-session.md  # セッション分離ルール
├── scripts/
│   └── cwt.sh               # メインスクリプト
└── README.md
```

## Playwrightセッション分離

各worktreeには環境変数 `PLAYWRIGHT_CLI_SESSION` が自動設定され、ブラウザセッションが分離されます。これにより、複数のClaude Codeセッションが同じブラウザを操作する問題を防ぎます。

手動起動時も同様に設定可能:

```bash
PLAYWRIGHT_CLI_SESSION=issue-42 claude --worktree issue-42
```

## アンインストール

```bash
# プラグインを無効化
claude plugin remove cwt-cli

# ~/bin のスクリプトを削除（コピーで運用している場合）
rm ~/bin/cwt
```

## ライセンス

MIT

