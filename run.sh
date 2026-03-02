#!/bin/bash
set -euo pipefail

MAX_ITERATIONS=3
PASS_THRESHOLD=80
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors for terminal output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[pipeline]${NC} $1"; }
success() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[x]${NC} $1"; }

# --- Process a single character sheet ---
process_file() {
  local file="$1"
  local name
  name=$(basename "$file" | sed 's/\.[^.]*$//')

  log "Processing: ${name}"
  log "========================================"

  # ── AGENT 1: ANALYZER ──
  log "Agent 1 (Analyzer): Extracting character sheet data..."

  claude -p \
    --system-prompt "$(cat "${SCRIPT_DIR}/agents/analyzer_prompt.md")" \
    --output-file "${SCRIPT_DIR}/specs/${name}.json" \
    --max-turns 5 \
    "Analyze this character sheet image and output a complete JSON spec. Be exhaustive — every field, every section, every value. The image file is at: ${file}"

  if [ ! -f "${SCRIPT_DIR}/specs/${name}.json" ]; then
    fail "Analyzer failed to produce spec for ${name}"
    return 1
  fi
  success "Spec created: specs/${name}.json"

  # ── ITERATION LOOP ──
  local iteration=0
  local passed=false
  local score=0
  local feedback=""

  while [ $iteration -lt $MAX_ITERATIONS ]; do
    iteration=$((iteration + 1))
    log "Build iteration ${iteration}/${MAX_ITERATIONS}"

    # ── AGENT 2: BUILDER ──
    log "Agent 2 (Builder): Generating interactive HTML..."

    local builder_input="Build an interactive HTML character sheet from this spec.

SPEC:
$(cat "${SCRIPT_DIR}/specs/${name}.json")

ORIGINAL IMAGE: ${file}"

    if [ -n "$feedback" ]; then
      builder_input="${builder_input}

TESTER FEEDBACK FROM PREVIOUS ITERATION (fix these issues):
${feedback}"
    fi

    claude -p \
      --system-prompt "$(cat "${SCRIPT_DIR}/agents/builder_prompt.md")" \
      --output-file "${SCRIPT_DIR}/builds/${name}.html" \
      --max-turns 10 \
      "$builder_input"

    if [ ! -f "${SCRIPT_DIR}/builds/${name}.html" ]; then
      fail "Builder failed to produce HTML for ${name} (iteration ${iteration})"
      continue
    fi
    success "HTML built: builds/${name}.html"

    # ── AGENT 3: TESTER ──
    log "Agent 3 (Tester): Testing build quality..."

    claude -p \
      --system-prompt "$(cat "${SCRIPT_DIR}/agents/tester_prompt.md")" \
      --output-file "${SCRIPT_DIR}/reports/${name}_report.json" \
      --max-turns 10 \
      --allowedTools "mcp__chrome-devtools" \
      "Test this character sheet build.

ORIGINAL IMAGE: ${file}
BUILT HTML FILE: ${SCRIPT_DIR}/builds/${name}.html
SPEC: $(cat "${SCRIPT_DIR}/specs/${name}.json")

Open the HTML file in Chrome using the DevTools MCP, visually inspect it, and compare against the original image. Output your test report as JSON."

    if [ ! -f "${SCRIPT_DIR}/reports/${name}_report.json" ]; then
      warn "Tester failed to produce report, using build as-is"
      break
    fi

    # Parse test results
    score=$(jq -r '.score // 0' "${SCRIPT_DIR}/reports/${name}_report.json" 2>/dev/null || echo "0")
    passed=$(jq -r '.pass // false' "${SCRIPT_DIR}/reports/${name}_report.json" 2>/dev/null || echo "false")
    feedback=$(jq -r '.flaws // [] | map("- [\(.severity)] \(.description): \(.fix)") | join("\n")' "${SCRIPT_DIR}/reports/${name}_report.json" 2>/dev/null || echo "")

    log "Score: ${score}/100 | Pass: ${passed}"

    if [ "$passed" = "true" ] || [ "$score" -ge $PASS_THRESHOLD ] 2>/dev/null; then
      success "Approved after ${iteration} iteration(s) with score ${score}"
      passed=true
      break
    else
      warn "Failed (score: ${score}). Flaws found:"
      echo "$feedback" | head -10
    fi
  done

  # Copy best build to output
  cp "${SCRIPT_DIR}/builds/${name}.html" "${SCRIPT_DIR}/output/${name}.html"

  if [ "$passed" = true ]; then
    success "Final output: output/${name}.html"
  else
    warn "Max iterations reached. Best attempt saved: output/${name}.html"
  fi

  echo ""
}

# --- Main ---
main() {
  log "Character Sheet Pipeline"
  log "========================================"

  # Check for Claude Code
  if ! command -v claude &> /dev/null; then
    fail "Claude Code CLI not found. Install it first: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
  fi

  # Check for jq (needed for bash version)
  if ! command -v jq &> /dev/null; then
    fail "jq not found. Install it: https://github.com/jqlang/jq/releases"
    exit 1
  fi

  # Process specific file or all files in input/
  if [ $# -gt 0 ] && [ "$1" != "--watch" ]; then
    process_file "$1"
  else
    local files_found=0
    for file in "${SCRIPT_DIR}"/input/*.{png,jpg,jpeg,pdf,webp,PNG,JPG,JPEG,PDF,WEBP}; do
      [ -f "$file" ] || continue
      files_found=$((files_found + 1))
      process_file "$file"
    done

    if [ $files_found -eq 0 ]; then
      warn "No files found in input/. Drop character sheet images or PDFs there first."
      exit 0
    fi

    success "Pipeline complete. Processed ${files_found} file(s)."
  fi

  # Optional: deploy
  if [ -f "${SCRIPT_DIR}/deploy.sh" ]; then
    read -p "Deploy output files to server? (y/N): " deploy_choice
    if [[ "$deploy_choice" =~ ^[Yy]$ ]]; then
      bash "${SCRIPT_DIR}/deploy.sh"
    fi
  fi
}

main "$@"
