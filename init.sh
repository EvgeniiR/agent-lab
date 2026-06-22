#!/usr/bin/env bash
set -euo pipefail

AGENT_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Prompt helpers ────────────────────────────────────────────────────────────

prompt_target_dir() {
  local input
  read -r -p "Target directory [.]: " input </dev/tty
  echo "${input:-.}"
}

prompt_template() {
  local input
  while true; do
    echo "Select template:" >/dev/tty
    echo "  1) default   — all roles on DeepSeek v4 Pro" >/dev/tty
    echo "  2) advanced  — intake/reviewer on Qwen3.7, planner on GLM-5.2, implementer on DeepSeek v4 Pro, pipeline on DeepSeek v4 Flash" >/dev/tty
    read -r -p "Template [1]: " input </dev/tty
    case "${input:-1}" in
      1|default)  echo "default";  return ;;
      2|advanced) echo "advanced"; return ;;
      *) echo "  Please enter 1 or 2." >/dev/tty ;;
    esac
  done
}

prompt_confirm() {
  local target="$1" template="$2" input
  echo "" >/dev/tty
  echo "  dir:      $target" >/dev/tty
  echo "  template: $template" >/dev/tty
  echo "" >/dev/tty
  read -r -p "Proceed? [Y/n]: " input </dev/tty
  case "${input:-y}" in
    [Yy]*) return 0 ;;
    *)     echo "Aborted." >/dev/tty; exit 0 ;;
  esac
}

# ── Argument / interactive intake ─────────────────────────────────────────────

if [ $# -ge 1 ]; then
  TARGET_DIR="$1"
else
  TARGET_DIR="$(prompt_target_dir)"
fi

if [ $# -ge 2 ]; then
  TEMPLATE="$2"
else
  TEMPLATE="$(prompt_template)"
fi

mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ "$TARGET_DIR" = "$AGENT_LAB_DIR" ]; then
  echo "ERROR: target dir is the framework repo itself. Pass a project path." >&2
  exit 1
fi

# Confirm only in interactive mode (when args were missing)
if [ $# -lt 2 ]; then
  prompt_confirm "$TARGET_DIR" "$TEMPLATE"
fi

# ── Core logic ────────────────────────────────────────────────────────────────

mkdir -p "$TARGET_DIR/opencode-agents" "$TARGET_DIR/workspace"

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

if [ "$TEMPLATE" = "advanced" ]; then
  copy_once "$AGENT_LAB_DIR/opencode.advanced.json.template" "$TARGET_DIR/opencode.json" "opencode.json"
else
  copy_once "$AGENT_LAB_DIR/opencode.json.template" "$TARGET_DIR/opencode.json" "opencode.json"
fi

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
