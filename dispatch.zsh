#!/bin/zsh
# orgo: run Claude Code on OpenRouter with a model picked per task.
# Reads the project's HANDOFF.md, picks the best value model for each open task
# (live prices + benchmark sites), shows you the plan, then runs tasks one by one
# at max effort. Lives in ~/.orgo, outside your workspace, so no session can edit it.

ORGO_DIR="$HOME/.orgo"
source "$ORGO_DIR/config" || { print "❌ Missing $ORGO_DIR/config. Re-run the installer."; exit 1; }
WS="$ORGO_WORKSPACE"
PLANNER_MODEL="${ORGO_PLANNER_MODEL:-xiaomi/mimo-v2.6-pro}"
FALLBACK_MODEL="${ORGO_FALLBACK_MODEL:-xiaomi/mimo-v2.6-pro}"
SETTINGS="$ORGO_DIR/session-settings.json"

say()  { print -r -- "$*"; }
line() { say "--------------------------------------------------------------"; }

command -v claude >/dev/null 2>&1 || { say "❌ Claude Code isn't installed. Get it at https://claude.com/claude-code then try again."; exit 1; }

KEY=$(security find-generic-password -a "$USER" -s orgo-openrouter-key -w 2>/dev/null)
[[ "$KEY" == sk-or-* ]] || { say "❌ No OpenRouter key saved. Re-run the installer."; exit 1; }

# Every call goes to OpenRouter, never the Anthropic API.
run_claude() {
  local model="$1"; shift
  ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
  ANTHROPIC_AUTH_TOKEN="$KEY" \
  ANTHROPIC_API_KEY="" \
  ANTHROPIC_MODEL="$model" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" \
  CLAUDE_CODE_SUBAGENT_MODEL="$model" \
  CLAUDE_CODE_EFFORT_LEVEL="max" \
  command claude --settings "$SETTINGS" "$@"
}

# ---------- 1. Pick the project ----------
mkdir -p "$WS"; cd "$WS" || exit 1
find_handoff() { for f in HANDOFF.md PROGRESS.md TODO.md; do [[ -f "$f" ]] && { print -r -- "$f"; return 0; }; done; return 1; }
projects=("${(@f)$(for d in *(N/); do print -r -- "$d"; done)}"); projects=(${projects:#})
if [[ -n "$1" ]]; then
  [[ -d "$WS/$1" ]] || { say "❌ No project folder named '$1' in $WS"; exit 1; }
  cd "$WS/$1"
elif (( ${#projects} == 1 )); then
  cd "$WS/${projects[1]}"
elif (( ${#projects} > 1 )); then
  say "📂 Which project? (name or number)"
  i=1; for p in $projects; do say "  $i) $p"; ((i++)); done
  printf "> "; read -r n
  [[ "$n" != <-> ]] && n=${projects[(Ie)$n]}
  [[ "$n" == <-> ]] && (( n >= 1 && n <= ${#projects} )) || { say "Not a project I know."; exit 1; }
  cd "$WS/${projects[$n]}"
fi
say "📁 Project: ${PWD#$WS/}"

# ---------- 2. Get the newest work ----------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git fetch -q origin 2>/dev/null
  cur=$(git branch --show-current)
  newest=$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/remotes/origin 2>/dev/null | grep -v '^origin/HEAD$' | grep -v '^origin$' | head -1)
  newest=${newest#origin/}
  if [[ -n "$newest" && "$newest" != "$cur" ]]; then
    printf "🌿 Newest work is on '$newest' (you're on '$cur'). Switch? Return = yes · n = stay: "; read -r ans
    [[ "$ans" != [nN]* ]] && { git switch -q "$newest" 2>/dev/null || git switch -q -c "$newest" --track "origin/$newest" 2>/dev/null || say "⚠️  Couldn't switch, staying on '$cur'."; }
  fi
  [[ -z "$(git status --porcelain 2>/dev/null)" ]] && git pull -q --ff-only 2>/dev/null
  grep -qx ".orgo/" .git/info/exclude 2>/dev/null || print ".orgo/" >> .git/info/exclude
  say "🌿 Branch: $(git branch --show-current)"
fi

HANDOFF=$(find_handoff)
if [[ -n "$HANDOFF" ]]; then TASKS=$(<"$HANDOFF")
else
  say "📝 No HANDOFF.md here. Type tasks, one per line, empty line when done:"
  while IFS= read -r t && [[ -n "$t" ]]; do TASKS+="- [ ] $t"$'\n'; done
  [[ -z "$TASKS" ]] && { say "Nothing to do."; exit 0; }
fi

# ---------- 3. Live prices ----------
say "💸 Fetching live OpenRouter prices..."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
curl -s --max-time 30 https://openrouter.ai/api/v1/models -o "$TMP/models.json"
CANDIDATES=$(osascript -l JavaScript "$ORGO_DIR/models.js" "$TMP/models.json" 2>/dev/null)
VALID_IDS=("${(@f)$(print -r -- "$CANDIDATES" | cut -d'|' -f1 | tr -d ' ')}")

# ---------- 4. Plan ----------
say "🧠 Planning with $PLANNER_MODEL (max effort)..."
PROMPT="You are a model dispatcher for coding sessions. Do NOT edit any files.
For each OPEN task below, pick ONE OpenRouter model with the best quality for that kind of task at the lowest cost. Spend on hard tasks, save on easy ones.
RULES
1. Pick ONLY ids from CANDIDATES (id | input \$/M | output \$/M | context).
2. Check current benchmarks with WebFetch first: openrouter.ai/<model-id> pages (they show Artificial Analysis scores), https://openrouter.ai/rankings, https://artificialanalysis.ai/models. Match benchmark to task type (agentic coding, frontend, debugging, long-context refactor, data, docs).
3. Keep each task title EXACTLY as written. Skip done tasks. Dependencies first. Max 8 tasks.
4. Output between a line PLAN_START and a line PLAN_END, one task per line:
<n>|||<task title verbatim>|||<model id>|||<estimated USD, like 0.40>|||<why, max 15 words>

CANDIDATES
$CANDIDATES

TASKS
$TASKS"
PLAN=$(run_claude "$PLANNER_MODEL" -p "$PROMPT" --disallowedTools Bash Edit Write NotebookEdit 2>"$TMP/err" | awk '/^PLAN_START/{f=1;next}/^PLAN_END/{f=0}f && /\|\|\|/')
[[ -z "$PLAN" ]] && { say "❌ The planner didn't return a plan:"; tail -5 "$TMP/err"; exit 1; }

titles=(); models=(); costs=(); whys=()
while IFS= read -r row; do
  parts=("${(@s:|||:)row}")
  m="${parts[3]// /}"; w="${parts[5]}"
  if [[ -z "$m" || "$m" == anthropic/* || ( -n "$CANDIDATES" && ${VALID_IDS[(Ie)$m]} -eq 0 ) ]]; then
    w="(fallback: planner picked '${m:-nothing}') $w"; m="$FALLBACK_MODEL"
  fi
  titles+=("${parts[2]}"); models+=("$m"); costs+=("${parts[4]// /}"); whys+=("$w")
done <<< "$PLAN"

mkdir -p .orgo; { print "# plan $(date '+%Y-%m-%d %H:%M')"; for i in {1..${#titles}}; do print -r -- "$i. ${titles[$i]} -> ${models[$i]} (~\$${costs[$i]})"; done; } >> .orgo/plans.md

while true; do
  line; say "🗺️  PLAN (OpenRouter, max effort, nothing runs until you say so)"; line
  for i in {1..${#titles}}; do say "$i) ${titles[$i]}"; say "   🤖 ${models[$i]}   ~\$${costs[$i]}   ${whys[$i]}"; done; line
  printf "Return = run · c = change a model · q = quit: "; read -r ans
  case "$ans" in
    "") break ;;
    q|Q) say "Stopped. Nothing ran."; exit 0 ;;
    c|C) printf "Task number: "; read -r n
         [[ "$n" == <-> ]] && (( n >= 1 && n <= ${#titles} )) || { say "Not a task number."; continue; }
         printf "Model id: "; read -r m
         if [[ "$m" == anthropic/* ]] || { [[ -n "$CANDIDATES" ]] && (( ${VALID_IDS[(Ie)$m]} == 0 )); }; then say "❌ Not an allowed model."; else models[$n]="$m"; whys[$n]="(changed by you)"; fi ;;
  esac
done

# ---------- 5. Run ----------
total=${#titles}
for i in {1..$total}; do
  line; say "▶️  Task $i of $total: ${titles[$i]}  ·  🤖 ${models[$i]}"
  if (( i > 1 )); then printf "Return = start · s = skip · q = stop: "; read -r ans
    case "$ans" in s|S) continue ;; q|Q) exit 0 ;; esac; fi
  ORGO_TASK="$i/$total" run_claude "${models[$i]}" ${=ORGO_EXTRA_ARGS} "Work on task $i of $total from ${HANDOFF:-the task list}: \"${titles[$i]}\". Do ONLY this task. When finished, update ${HANDOFF:-HANDOFF.md} (mark it done, note what changed) and tell me to type /exit so the next task can start."
done
line; say "✅ All done. Plan log: .orgo/plans.md"
