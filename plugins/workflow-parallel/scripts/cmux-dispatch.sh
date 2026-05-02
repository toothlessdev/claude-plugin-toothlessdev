#!/usr/bin/env bash
set -euo pipefail

# cmux-dispatch.sh
#
# workflow-parallel Stage 7 의 cmux pane dispatch 스크립트.
# 1개 cmux surface 에 대해:
#   /exit (기존 claude 종료) → cd <worktree> && claude --dangerously-skip-permissions →
#   boot prompt send → Enter → read-screen 으로 작업 시작 확인.
#
# 사용법:
#   bash scripts/cmux-dispatch.sh \
#     --surface surface:3 \
#     --worktree /path/to/worktree \
#     --boot-prompt-file /tmp/boot-MCP-1234.md
#
#   --boot-prompt-file 대신 --boot-prompt "<text>" 인라인 가능.

SURFACE=""
WORKTREE=""
BOOT_FILE=""
BOOT_INLINE=""
SKIP_EXIT=0
SETTLE_MS=1500     # /exit 후 claude 재시작 대기 (ms)
PROMPT_DELAY_MS=2000  # claude restart 후 prompt 입력 전 대기

usage() {
  sed -n '4,15p' "$0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface)          SURFACE="$2";      shift 2 ;;
    --worktree)         WORKTREE="$2";     shift 2 ;;
    --boot-prompt-file) BOOT_FILE="$2";    shift 2 ;;
    --boot-prompt)      BOOT_INLINE="$2";  shift 2 ;;
    --skip-exit)        SKIP_EXIT=1;       shift ;;
    -h|--help) usage ;;
    *) echo "[err] unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$SURFACE" || -z "$WORKTREE" ]]; then
  echo "[err] --surface 와 --worktree 는 필수" >&2
  usage
fi

if [[ -n "$BOOT_FILE" && -n "$BOOT_INLINE" ]]; then
  echo "[err] --boot-prompt-file 와 --boot-prompt 동시 지정 불가" >&2
  exit 2
fi

if [[ -z "$BOOT_FILE" && -z "$BOOT_INLINE" ]]; then
  echo "[err] --boot-prompt-file 또는 --boot-prompt 중 하나는 필수" >&2
  exit 2
fi

if [[ -n "$BOOT_FILE" && ! -f "$BOOT_FILE" ]]; then
  echo "[err] boot-prompt 파일 미존재: $BOOT_FILE" >&2
  exit 3
fi

if [[ ! -d "$WORKTREE" ]]; then
  echo "[err] worktree 디렉토리 미존재: $WORKTREE" >&2
  exit 3
fi

if ! command -v cmux >/dev/null 2>&1; then
  echo "[err] cmux CLI not found in PATH" >&2
  exit 4
fi

log() { printf '[cmux-dispatch] %s\n' "$*"; }

sleep_ms() {
  local ms="$1"
  awk -v ms="$ms" 'BEGIN{ system(sprintf("sleep %f", ms/1000.0)) }'
}

cmux_send() {
  cmux send --surface "$SURFACE" "$1"
}

cmux_send_key() {
  cmux send-key --surface "$SURFACE" "$1"
}

# Step 1: 기존 claude 종료
if [[ $SKIP_EXIT -eq 0 ]]; then
  log "[$SURFACE] /exit (기존 claude 세션 종료)"
  cmux_send "/exit"
  cmux_send_key "Enter"
  sleep_ms "$SETTLE_MS"
fi

# Step 2: cd + claude restart
START_CMD="cd \"$WORKTREE\" && claude --dangerously-skip-permissions"
log "[$SURFACE] $START_CMD"
cmux_send "$START_CMD"
cmux_send_key "Enter"
sleep_ms "$PROMPT_DELAY_MS"

# Step 3: boot prompt 입력
if [[ -n "$BOOT_FILE" ]]; then
  BOOT_TEXT="$(cat "$BOOT_FILE")"
else
  BOOT_TEXT="$BOOT_INLINE"
fi

log "[$SURFACE] boot prompt 입력 (${#BOOT_TEXT} chars)"
cmux_send "$BOOT_TEXT"
sleep_ms 500
cmux_send_key "Enter"

# Step 4: 검증 — read-screen 으로 작업 시작 흔적 확인
sleep_ms 3000
SCREEN="$(cmux read-screen --surface "$SURFACE" --lines 40 2>/dev/null || true)"

if [[ -z "$SCREEN" ]]; then
  log "[$SURFACE] [warn] read-screen 결과 비어있음 — 수동 확인 권장"
else
  log "[$SURFACE] read-screen tail:"
  printf '%s\n' "$SCREEN" | tail -n 8 | sed 's/^/    /'
fi

log "[$SURFACE] dispatch 완료. worktree=$WORKTREE"
