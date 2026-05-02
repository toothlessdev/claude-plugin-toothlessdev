#!/usr/bin/env bash
set -euo pipefail

# git-worktree-setup.sh
#
# workflow-parallel Stage 6 의 worktree 일괄 생성 스크립트.
# fetch → sequential worktree add → pnpm 모노레포 감지 시 sequential install → untracked 보정.
#
# 사용법:
#   bash scripts/git-worktree-setup.sh \
#     --main main \
#     --repo /path/to/main-repo \
#     --plan /path/to/plan.md \
#     --todo /path/to/main-repo/TODO.md \
#     --pair MCP-1234:auth-refactor \
#     --pair MCP-1235:logger-migration

MAIN_BRANCH=""
REPO_PATH=""
PLAN_PATH=""
TODO_PATH=""
PAIRS=()

usage() {
  sed -n '4,16p' "$0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --main)  MAIN_BRANCH="$2"; shift 2 ;;
    --repo)  REPO_PATH="$2";   shift 2 ;;
    --plan)  PLAN_PATH="$2";   shift 2 ;;
    --todo)  TODO_PATH="$2";   shift 2 ;;
    --pair)  PAIRS+=("$2");    shift 2 ;;
    -h|--help) usage ;;
    *) echo "[err] unknown arg: $1" >&2; usage ;;
  esac
done

if [[ -z "$MAIN_BRANCH" || -z "$REPO_PATH" || ${#PAIRS[@]} -eq 0 ]]; then
  echo "[err] --main, --repo, --pair 는 필수" >&2
  usage
fi

if [[ ! -d "$REPO_PATH/.git" && ! -f "$REPO_PATH/.git" ]]; then
  echo "[err] $REPO_PATH 는 git repo 가 아님" >&2
  exit 2
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
REPO_NAME="$(basename "$REPO_PATH")"
PARENT_DIR="$(dirname "$REPO_PATH")"

log() { printf '[worktree-setup] %s\n' "$*"; }

# Step 1: fetch
log "fetch origin $MAIN_BRANCH"
git -C "$REPO_PATH" fetch origin "$MAIN_BRANCH"

# Step 2: pnpm 모노레포 감지
IS_PNPM_MONOREPO=0
if [[ -f "$REPO_PATH/pnpm-workspace.yaml" || -f "$REPO_PATH/pnpm-lock.yaml" ]]; then
  IS_PNPM_MONOREPO=1
  log "pnpm 프로젝트 감지 — worktree 마다 sequential install 예정"
fi

# Step 3: 각 pair 마다 worktree add (sequential)
declare -a CREATED_PATHS=()
declare -a CREATED_BRANCHES=()
declare -a CREATED_KEYS=()

for pair in "${PAIRS[@]}"; do
  KEY="${pair%%:*}"
  SLUG="${pair#*:}"

  if [[ -z "$KEY" || -z "$SLUG" || "$KEY" == "$pair" ]]; then
    echo "[err] --pair 형식 오류: '$pair' (TICKET:slug)" >&2
    exit 3
  fi

  BRANCH="${KEY}-${SLUG}"
  WT_PATH="${PARENT_DIR}/${REPO_NAME}-${KEY}"

  if [[ -e "$WT_PATH" ]]; then
    echo "[err] worktree 경로가 이미 존재: $WT_PATH" >&2
    exit 4
  fi

  log "worktree add $WT_PATH ($BRANCH from origin/$MAIN_BRANCH)"
  git -C "$REPO_PATH" worktree add "$WT_PATH" -b "$BRANCH" "origin/$MAIN_BRANCH"

  CREATED_PATHS+=("$WT_PATH")
  CREATED_BRANCHES+=("$BRANCH")
  CREATED_KEYS+=("$KEY")
done

# Step 4: untracked plan / TODO 보정
copy_if_untracked() {
  local src="$1"
  local label="$2"
  if [[ -z "$src" ]]; then return 0; fi
  if [[ ! -f "$src" ]]; then
    log "$label 미존재 — 건너뜀 ($src)"
    return 0
  fi

  local rel=""
  if [[ "$src" == "$REPO_PATH"/* ]]; then
    rel="${src#$REPO_PATH/}"
  fi

  local is_untracked=0
  if [[ -n "$rel" ]]; then
    if ! git -C "$REPO_PATH" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      is_untracked=1
    fi
  else
    is_untracked=1  # repo 밖 파일은 항상 cp
  fi

  if [[ $is_untracked -eq 0 ]]; then
    log "$label 은 tracked — worktree checkout 으로 자동 따라감"
    return 0
  fi

  for wt in "${CREATED_PATHS[@]}"; do
    local dest
    if [[ -n "$rel" ]]; then
      dest="$wt/$rel"
    else
      dest="$wt/$(basename "$src")"
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    log "보정: $label → $dest"
  done
}

copy_if_untracked "$TODO_PATH" "TODO.md"
copy_if_untracked "$PLAN_PATH" "plan"

# Step 5: pnpm install (sequential)
if [[ $IS_PNPM_MONOREPO -eq 1 ]]; then
  TOTAL=${#CREATED_PATHS[@]}
  IDX=0
  for wt in "${CREATED_PATHS[@]}"; do
    IDX=$((IDX + 1))
    log "[$IDX/$TOTAL] pnpm install @ $wt"
    (cd "$wt" && pnpm install)
  done
fi

# Step 6: 매핑 보고
log "=== 생성 결과 ==="
for i in "${!CREATED_KEYS[@]}"; do
  printf '  %s\t%s\t%s\n' "${CREATED_KEYS[$i]}" "${CREATED_BRANCHES[$i]}" "${CREATED_PATHS[$i]}"
done

log "완료. ${#CREATED_PATHS[@]} 개 worktree 준비됨."
