#!/usr/bin/env bash
set -euo pipefail

AGENT_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$(pwd)}"
mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ "$TARGET_DIR" = "$AGENT_LAB_DIR" ]; then
  echo "ERROR: target dir is the framework repo itself. Pass a project path." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR/opencode-agents" "$TARGET_DIR/workspace/tasks"

created=() skipped=() overrides=()

link_agent() {
  local name="$1"
  local src="$AGENT_LAB_DIR/agents/${name}.md"
  local dst="$TARGET_DIR/opencode-agents/${name}.md"

  if [ -f "$dst" ] && [ ! -L "$dst" ]; then
    overrides+=("opencode-agents/${name}.md")
  else
    ln -sf "$src" "$dst"
    created+=("opencode-agents/${name}.md -> $src")
  fi
}

link_agent intake
link_agent planner
link_agent implementer
link_agent reviewer
link_agent pipeline

copy_once() {
  local src="$1" dst="$2" label="$3"
  if [ -e "$dst" ]; then
    skipped+=("$label")
  else
    cp "$src" "$dst"
    created+=("$label")
  fi
}

copy_once "$AGENT_LAB_DIR/opencode.json.template" "$TARGET_DIR/opencode.json" "opencode.json"

echo ""
echo "=== agent-lab init: $TARGET_DIR ==="
for f in "${created[@]+"${created[@]}"}";   do echo "  created  $f"; done
for f in "${skipped[@]+"${skipped[@]}"}";   do echo "  skipped  $f (exists)"; done
for f in "${overrides[@]+"${overrides[@]}"}"; do echo "  override $f (real file kept)"; done
echo ""
echo "Next steps:"
echo "  1. Create AGENTS.md — run 'opencode /init' to bootstrap, then trim to <50 lines"
echo "  2. Review opencode.json (adjust models if needed)"
echo "  3. Start: opencode run --agent pipeline '<your prompt>'"
echo ""
echo "To override an agent prompt for this project:"
echo "  rm opencode-agents/<role>.md && cp \$AGENT_LAB_DIR/agents/<role>.md opencode-agents/"
echo "  then edit opencode-agents/<role>.md freely"
