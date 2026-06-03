#!/usr/bin/env bash
#
# articular.sh — thin curl wrappers around the Articular REST API.
#
# Backs the Articular "loop" skill: open a board, externalize your reasoning as
# live sticky notes, and keep a human in the loop with a URL to watch and steer.
# Every sticky you create broadcasts over WebSocket, so a human with the board
# open sees your thinking appear in real time.
#
# Auth — an Articular API key (Bearer). Create one (while signed in) at:
#   $ARTICULAR_WEB_URL/settings/api-keys
#
# Required env:
#   ARTICULAR_API_KEY     e.g. art_xxxxx
# Optional env:
#   ARTICULAR_API_URL     default https://api.articular.ai
#   ARTICULAR_WEB_URL     default https://articular.ai
#   ARTICULAR_PROJECT     project id to hold boards (else a project named
#                         "Agent boards" is found-or-created)
#
# Requires: curl, jq
set -euo pipefail

API_URL="${ARTICULAR_API_URL:-https://api.articular.ai}"
WEB_URL="${ARTICULAR_WEB_URL:-https://articular.ai}"
DEFAULT_PROJECT_NAME="Agent boards"

die() { echo "articular: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required (e.g. brew install jq)"
[ -n "${ARTICULAR_API_KEY:-}" ] || \
  die "set ARTICULAR_API_KEY — create one at $WEB_URL/settings/api-keys"

# _api METHOD PATH [JSON_BODY] -> prints response body; exits non-zero on HTTP >= 400.
# Call as a standalone assignment (resp="$(_api ...)") so set -e catches failures;
# never inline as `local x="$(_api ...)"` — `local` would mask the exit code.
_api() {
  local method="$1" path="$2" body="${3:-}" tmp http
  tmp="$(mktemp)"
  local args=(-sS -o "$tmp" -w '%{http_code}' -X "$method" "$API_URL$path"
              -H "Authorization: Bearer $ARTICULAR_API_KEY")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" --data "$body")
  http="$(curl "${args[@]}")" || { rm -f "$tmp"; die "network error: $method $path"; }
  if [ "$http" -ge 400 ]; then
    { echo "articular: $method $path -> HTTP $http"; cat "$tmp"; echo; } >&2
    rm -f "$tmp"; exit 1
  fi
  cat "$tmp"; rm -f "$tmp"
}

_board_link() { printf '%s/b/%s/%s' "$WEB_URL" "$1" "$2"; }  # shortcode slug

_assert_num() { case "$1" in ''|*[!0-9]*) die "expected a numeric id, got: '$1'";; esac; }

# Find one of the caller's boards by id; prints the board JSON object (which
# carries projectId, shortcode, slug, agentStatus). Pages /me/boards as needed.
_find_board() {
  local boardId="$1" cursor="" page hit path
  _assert_num "$boardId"
  while :; do
    path="/api/me/boards?limit=100"
    [ -n "$cursor" ] && path="$path&cursor=$cursor"
    page="$(_api GET "$path")"
    hit="$(echo "$page" | jq -c --argjson b "$boardId" '.boards[] | select(.id==$b)')"
    [ -n "$hit" ] && { echo "$hit"; return 0; }
    cursor="$(echo "$page" | jq -r '.nextCursor // empty')"
    [ -z "$cursor" ] && break
  done
  die "board $boardId not found among your boards (is the key for the right account?)"
}

# Resolve the project to create boards in: ARTICULAR_PROJECT, else a project
# named "$DEFAULT_PROJECT_NAME" (found or created).
_ensure_project() {
  if [ -n "${ARTICULAR_PROJECT:-}" ]; then echo "$ARTICULAR_PROJECT"; return 0; fi
  local list id created
  list="$(_api GET "/api/projects")"
  id="$(echo "$list" | jq -r --arg n "$DEFAULT_PROJECT_NAME" \
        'first(.projects[] | select(.name==$n) | .id) // empty')"
  [ -n "$id" ] && { echo "$id"; return 0; }
  created="$(_api POST "/api/projects" "$(jq -n --arg n "$DEFAULT_PROJECT_NAME" '{name:$n}')")"
  echo "$created" | jq -r '.id'
}

usage() {
  cat >&2 <<EOF
articular.sh — externalize agent reasoning onto a live Articular board.

Usage:
  articular.sh create-board "<title>" [--context "<text>"] [--transcript-file <path>] [--project <id>]
  articular.sh add-sticky <boardId> "<content>" [--category <cat>] [--group "<label>"] [--x <n> --y <n>] [--color <#hex>]
  articular.sh add-stickies-md <boardId> <file|->        # batch: each sticky is "## N. Title" + optional \`category\` line
  articular.sh organize <boardId>                        # let Articular's canvas agent tidy the layout
  articular.sh summarize <boardId> [--wait]              # generate a themed summary (needs >=1 sticky)
  articular.sh summary <boardId>                         # print the latest summary (markdown)
  articular.sh status <boardId>                          # agentStatus: empty | in_progress | ready
  articular.sh board-url <boardId>                       # print the shareable board URL
  articular.sh boards                                    # list your boards + status + URL

Categories: problem | request | insight | solution | brainstorm

Env: ARTICULAR_API_KEY (required), ARTICULAR_API_URL, ARTICULAR_WEB_URL, ARTICULAR_PROJECT
EOF
  exit "${1:-2}"
}

cmd_create_board() {
  local title="" context="" tfile="" project="" raw body resp boardId shortcode slug pid
  [ $# -gt 0 ] || usage
  title="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --context)         context="$2"; shift 2;;
      --transcript-file) tfile="$2"; shift 2;;
      --project)         project="$2"; shift 2;;
      *) die "unknown flag: $1";;
    esac
  done
  [ -n "$title" ] || die "create-board: title is required"

  # A board must be seeded with source material (the API rejects an empty board).
  # Use the supplied context/transcript as the board's source — for a reasoning
  # board this is the task or problem statement you're working through.
  if [ -n "$tfile" ]; then
    raw="$([ "$tfile" = "-" ] && cat || cat "$tfile")"
  elif [ -n "$context" ]; then
    raw="$context"
  else
    raw="$title"
  fi

  [ -n "$project" ] && ARTICULAR_PROJECT="$project"
  pid="$(_ensure_project)"
  body="$(jq -n --arg t "$title" --arg r "$raw" '{title:$t, rawTranscript:$r}')"
  resp="$(_api POST "/api/projects/$pid/boards" "$body")"
  boardId="$(echo "$resp"  | jq -r '.id')"
  shortcode="$(echo "$resp" | jq -r '.shortcode')"
  slug="$(echo "$resp"     | jq -r '.slug')"
  echo "Board ready — open it to watch your reasoning appear live:" >&2
  echo "  $(_board_link "$shortcode" "$slug")" >&2
  jq -n --argjson p "$pid" --argjson b "$boardId" --arg s "$shortcode" --arg g "$slug" \
        --arg u "$(_board_link "$shortcode" "$slug")" \
        '{projectId:$p, boardId:$b, shortcode:$s, slug:$g, url:$u}'
}

cmd_add_sticky() {
  local boardId="" content="" category="" group="" color="" x="" y="" board pid count col row body resp
  [ $# -ge 2 ] || usage
  boardId="$1"; content="$2"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --category) category="$2"; shift 2;;
      --group)    group="$2"; shift 2;;
      --color)    color="$2"; shift 2;;
      --x)        x="$2"; shift 2;;
      --y)        y="$2"; shift 2;;
      *) die "unknown flag: $1";;
    esac
  done
  board="$(_find_board "$boardId")"
  pid="$(echo "$board" | jq -r '.projectId')"

  # Auto-place on a tidy grid if no explicit coordinates were given.
  if [ -z "$x" ] || [ -z "$y" ]; then
    count="$(_api GET "/api/projects/$pid/boards/$boardId/stickies" | jq '.stickies | length')"
    col=$(( count % 5 )); row=$(( count / 5 ))
    x="${x:-$(( 120 + col * 240 ))}"
    y="${y:-$(( 120 + row * 220 ))}"
  fi

  body="$(jq -n --arg c "$content" --argjson x "$x" --argjson y "$y" \
            --arg cat "$category" --arg g "$group" --arg col "$color" '
    {content:$c, positionX:$x, positionY:$y}
    + (if $cat != "" then {category:$cat} else {} end)
    + (if $g   != "" then {groupLabel:$g} else {} end)
    + (if $col != "" then {color:$col} else {} end)')"
  resp="$(_api POST "/api/projects/$pid/boards/$boardId/stickies" "$body")"
  echo "$resp" | jq -r '"sticky #\(.id) added\(if .category then " [" + .category + "]" else "" end)"' >&2
  echo "$resp" | jq -c '{id, category, content}'
}

cmd_add_stickies_md() {
  local boardId="" file="" md board pid resp
  [ $# -ge 2 ] || usage
  boardId="$1"; file="$2"
  board="$(_find_board "$boardId")"
  pid="$(echo "$board" | jq -r '.projectId')"
  md="$([ "$file" = "-" ] && cat || cat "$file")"
  resp="$(_api POST "/api/projects/$pid/boards/$boardId/import-markdown-append" \
            "$(jq -n --arg m "$md" '{markdown:$m}')")"
  # Markdown shape: each sticky is an "## N. Title" heading (H1 "# ..." is the
  # board title), optionally followed by a `category` line, then a description.
  echo "$resp" | jq -r '"appended \(.added | length) stickies (\(.errors | length) parse errors)"' >&2
  echo "$resp" | jq -c '{added: (.added | length), errors}'
}

cmd_organize() {
  local boardId="${1:-}" board pid
  [ -n "$boardId" ] || usage
  board="$(_find_board "$boardId")"
  pid="$(echo "$board" | jq -r '.projectId')"
  _api POST "/api/projects/$pid/boards/$boardId/agent/organize" "{}" >/dev/null
  echo "canvas agent started — it will rearrange stickies live on the board" >&2
}

cmd_summarize() {
  local boardId="" wait="" board pid beforeGeneratedAt generatedAt pipelineStatus errorMessage started
  [ $# -gt 0 ] || usage
  boardId="$1"; shift
  [ "${1:-}" = "--wait" ] && wait=1
  board="$(_find_board "$boardId")"
  pid="$(echo "$board" | jq -r '.projectId')"
  beforeGeneratedAt="$(echo "$board" | jq -r '.summaryGeneratedAt // ""')"
  started="$(_api POST "/api/projects/$pid/boards/$boardId/summarize" "{}")"
  [ -z "$beforeGeneratedAt" ] && beforeGeneratedAt="$(echo "$started" | jq -r '.summaryGeneratedAt // ""')"
  echo "summary generation started" >&2
  if [ -n "$wait" ]; then
    for _ in $(seq 1 30); do
      sleep 2
      board="$(_find_board "$boardId")"
      pipelineStatus="$(echo "$board" | jq -r '.status // ""')"
      generatedAt="$(echo "$board" | jq -r '.summaryGeneratedAt // ""')"
      if [ "$pipelineStatus" = "error" ]; then
        errorMessage="$(echo "$board" | jq -r '.errorMessage // "unknown error"')"
        die "summary generation failed: $errorMessage"
      fi
      if [ "$pipelineStatus" = "done" ] && [ -n "$generatedAt" ] && [ "$generatedAt" != "$beforeGeneratedAt" ]; then
        cmd_summary "$boardId"
        return 0
      fi
    done
    echo "still waiting for a fresh summary after 60s — try: articular.sh summary $boardId" >&2
    return 1
  fi
}

cmd_summary() {
  local boardId="${1:-}" board pid
  [ -n "$boardId" ] || usage
  board="$(_find_board "$boardId")"
  pid="$(echo "$board" | jq -r '.projectId')"
  _api GET "/api/projects/$pid/boards/$boardId/summary?format=md"
}

cmd_status() {
  local boardId="${1:-}" board
  [ -n "$boardId" ] || usage
  board="$(_find_board "$boardId")"
  echo "$board" | jq -r '.agentStatus'
}

cmd_board_url() {
  local boardId="${1:-}" board
  [ -n "$boardId" ] || usage
  board="$(_find_board "$boardId")"
  echo "$board" | jq -r --arg w "$WEB_URL" '"\($w)/b/\(.shortcode)/\(.slug)"'
}

cmd_boards() {
  _api GET "/api/me/boards?limit=100" \
    | jq -r --arg w "$WEB_URL" \
      '.boards[] | "\(.id)\t\(.agentStatus)\t\($w)/b/\(.shortcode)/\(.slug)\t\(.title)"'
}

main() {
  local cmd="${1:-}"; [ -n "$cmd" ] && shift || usage
  case "$cmd" in
    create-board)     cmd_create_board "$@";;
    add-sticky)       cmd_add_sticky "$@";;
    add-stickies-md)  cmd_add_stickies_md "$@";;
    organize)         cmd_organize "$@";;
    summarize)        cmd_summarize "$@";;
    summary)          cmd_summary "$@";;
    status)           cmd_status "$@";;
    board-url)        cmd_board_url "$@";;
    boards)           cmd_boards "$@";;
    -h|--help|help)   usage 0;;
    *) die "unknown command: $cmd (run with --help)";;
  esac
}

main "$@"
