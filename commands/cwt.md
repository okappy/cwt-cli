---
description: Worktree + Playwright セッション管理（一覧・作成・削除・確認）＋ポート自動割り当て
argument-hint: [list|new <issue>|rm <branch>|clean|session|ports]
allowed-tools: Bash(git worktree:*), Bash(git gtr:*), Bash(git branch:*), Bash(git status:*), Bash(gh issue:*), Bash(playwright-cli:*), Bash(cwt:*)
model: haiku
---
# cwt - Worktree + Playwright セッション管理

Git worktree と Playwright CLI セッションの統合管理を行う。
worktree作成時にはアプリが使用するTCPポートを自動検出・割り当てする。

## 引数

- `$ARGUMENTS`:
  - `list` / 引数なし: 現在のworktree一覧 + Playwrightセッション一覧 + ポート割り当て
  - `new <issue-number>`: issue番号からworktree作成（ポート割り当て付き）
  - `rm <branch-name>`: worktreeとPlaywrightセッションを削除
  - `clean`: 不要なworktree + Playwrightセッションをクリーンアップ
  - `session`: 現在のPlaywrightセッション名を表示
  - `ports`: 現在のworktreeのポート情報を表示

## ポート管理の仕組み

### プロジェクトルートの `.cwt`（テンプレート）

`cwt <issue>` を初めて実行すると、プロジェクトのファイルをスキャンして
アプリが使用するTCPポートの種類を検出し、ルートに `.cwt` テンプレートを作成します。

スキャン優先順位: `.env.example` > `docker-compose.yml` > `Makefile` > `package.json` > `pyproject.toml` > `README.md` > `CLAUDE.md`

既存の `.cwt` がある場合は内容を表示し、そのまま使うか再スキャンするか確認します。

```text
# .cwt (ルート - テンプレート)
PORT_KEYS=3000,8080
```

### 各worktreeの `.cwt`（割り当て済みポート）

各worktreeには50000〜60000の範囲で固有のポートが割り当てられます。

```text
# .cwt (issue-42)
PORT_3000=52341
PORT_8080=54892
```

### ⚠️ アプリ起動時の必須手順

アプリ起動時は必ず `.cwt` のポートを使用してください。

```bash
source .cwt

# Node.js の例
npm run dev -- --port $PORT_3000

# Python / uvicorn の例
uvicorn main:app --port $PORT_8000
```

デフォルトポートを使うと、並行稼働中の他のworktreeとポートが競合します。

## 実行手順

### list（デフォルト）

```bash
echo "=== Git Worktrees ==="
git worktree list

echo ""
echo "=== Port Assignments ==="
# 各worktreeの.cwtを表示

echo ""
echo "=== Playwright Sessions ==="
playwright-cli list 2>/dev/null || echo "(no active sessions)"
```

### ports

```bash
cat .cwt
```

### session

```bash
echo "PLAYWRIGHT_CLI_SESSION=${PLAYWRIGHT_CLI_SESSION:-"(未設定 - default)"}"
```

### rm <branch-name>

```bash
playwright-cli -s=<branch-name> close 2>/dev/null || true
git worktree remove <path> --force
git branch -D <branch-name>
```

### clean

```bash
playwright-cli close-all 2>/dev/null || true
git worktree prune
git worktree list
```

## 注意事項

- worktree削除前に未コミット変更がないか確認すること
- `cwt` スクリプトを使えば、issue番号指定だけでworktree作成+ポート割り当て+Claude起動が可能
