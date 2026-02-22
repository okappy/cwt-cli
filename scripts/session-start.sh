#!/usr/bin/env bash
# session-start.sh - Claude Code SessionStart hook
# worktree内の .cwt を読み込み、ポート設定をClaudeのコンテキストに注入する

[ -f ".cwt" ] || exit 0

port_lines=$(grep '^PORT_[0-9]' ".cwt" 2>/dev/null || true)
[ -n "$port_lines" ] || exit 0

cat <<EOF
## CWT ポート設定（このworktree専用）

このworktreeには以下のポートが割り当てられています。
**アプリ起動時は必ずこのポートを使用してください。**
デフォルトポートを使用すると他のworktreeとポートが競合します。

\`\`\`
${port_lines}
\`\`\`

### アプリ起動方法
\`\`\`bash
source .cwt

# Node.js の例
npm run dev -- --port \$PORT_3000

# Python / uvicorn の例
uvicorn main:app --port \$PORT_8000
\`\`\`

ポート一覧の確認: \`cwt ports\`
EOF
