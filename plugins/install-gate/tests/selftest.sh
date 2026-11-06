#!/bin/bash
# Unit check for install-gate.
# Builds a throwaway project with a few audit records, feeds the hook the same JSON that Claude Code
# sends it, and checks the decision for each command: pass / deny / ask.
# Nothing is installed: the commands are only passed to the hook as text.
#
# A full pass here only tells you that the hook script decides correctly.
# Whether Claude Code actually calls the hook can only be seen with tests/live-check.sh.
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, jq, python3

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/gate.sh"
PASS=0; FAIL=0

command -v jq >/dev/null 2>&1 || { echo "jq was not found. Install jq and run this again."; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 was not found."; exit 1; }

ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/install-gate-selftest.XXXXXX") || { echo "could not create a temp folder"; exit 1; }
PROJ="$TMP/project"; REC="$PROJ/docs/tool-audits"; mkdir -p "$REC"

rec() { printf '%b' "$2" > "$REC/$1"; }
rec "jq-audit.md"                          "# jq install audit\n\nRisk: LOW\n\nReason in one line: official\n"
rec "2026-01-02_httpie-audit.md"           "# httpie\n\n> **Risk: LOW**\n"
rec "scope-pkg-audit.md"                   "Risk: LOW\n"
rec "github-audit.md"                      "Risk: LOW\n"
rec "secret-guard-25h-agent-kit-audit.md" "Risk: LOW\n"
rec "ripgrep-audit.md"                     "# ripgrep\n\nRisk: MID\n"
rec "badtool-audit.md"                     "Risk: HIGH\n"
rec "tmpl-audit.md"                        "# tmpl install audit\n\nRisk: <LOW | MID | HIGH>\n"
rec "two-audit.md"                         "Risk: LOW\nRisk: HIGH\n"
rec "emptyp-audit.md"                      ""
rec "norisk-audit.md"                      "I want this tool because it is handy.\n"
rec "notarecord.md"                        "Risk: LOW\n"
rec "prose-audit.md"                       "The tool has LOW overhead and is handy.\n"

# decision for a command: pass / deny / ask / (anything else = the raw output)
decide() { # command [path to gate.sh]
  local out
  out=$(jq -cn --arg c "$1" --arg d "$PROJ" '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
        | CLAUDE_PROJECT_DIR="$PROJ" bash "${2:-$GATE}" 2>/dev/null)
  if [ -z "$out" ]; then echo pass; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "broken-output"' 2>/dev/null || echo broken-output; fi
}
expect() { # expected command [path to gate.sh]
  local got; got=$(decide "$2" "$3")
  local label; label=$(printf '%s' "$2" | tr '\n' ' ' | cut -c1-70)
  [ "$got" = "$1" ] && ok "$1  $label" || ng "expected $1, got $got:  $label"
}

run_table() {
  while IFS='|' read -r want cmd; do
    [ -n "$want" ] || continue
    expect "$want" "$cmd"
  done
}

echo "[1] the three outcomes"
run_table <<'CASES'
pass|brew install jq
deny|brew install wget
ask|brew install ripgrep
ask|brew install badtool
CASES

echo "[2] what counts as a usable record"
run_table <<'CASES'
deny|brew install tmpl
deny|brew install two
deny|brew install emptyp
deny|brew install norisk
deny|brew install notarecord
deny|brew install prose
pass|pipx install httpie
deny|brew install jq wget
ask|brew install jq ripgrep
deny|brew install ripgrep wget
CASES

echo "[3] exact names: a different tap, scope or marketplace is a different tool"
run_table <<'CASES'
deny|brew install evil/tap/jq
deny|npm install -g @evil/jq
pass|npm install -g @scope/pkg
pass|npm install -g @scope/pkg@1.2.3
pass|npm install -g jq@1.0.0
deny|brew install jq-extras
deny|brew install j
pass|claude plugin install secret-guard@25h-agent-kit
deny|claude plugin install secret-guard@other-market
deny|claude plugin install other@market
CASES

echo "[4] brew"
run_table <<'CASES'
deny|brew reinstall wget
deny|brew --debug install wget
pass|brew --debug install jq
deny|brew install --cask wget
deny|/opt/homebrew/bin/brew install wget
pass|brew list
pass|brew info wget
pass|brew uninstall wget
pass|brew update
pass|brew install ./local-formula.rb
CASES

echo "[5] npm, pnpm, yarn, bun: only global installs"
run_table <<'CASES'
pass|npm install
pass|npm install lodash
pass|npm ci
deny|npm install -g typescript
deny|npm i -g typescript
deny|npm install --global typescript
deny|npm -g install typescript
deny|npm install typescript -g
deny|npm install -g --registry https://r.example.com typescript
pass|npm install -g --registry https://r.example.com jq
pass|npm install -g
deny|pnpm add -g typescript
pass|pnpm add typescript
deny|yarn global add typescript
pass|yarn add typescript
deny|bun add -g typescript
pass|bun add typescript
CASES

echo "[6] pipx, uv, pip"
run_table <<'CASES'
deny|pipx install black
pass|pipx install httpie==3.2.0
deny|uv tool install ruff
pass|uv tool install httpie
pass|uv pip install ruff
pass|uv sync
pass|pip install requests
pass|pip install -r requirements.txt
pass|pip install -e .
deny|pip install --user requests
deny|sudo pip install requests
deny|pip3 install --break-system-packages requests
pass|pip install --user -r requirements.txt
pass|pip install --user httpie
pass|pip install --user "httpie>=3.0"
pass|python3 -m pip install requests
deny|python3 -m pip install --user requests
deny|sudo -H pip install requests
CASES

echo "[7] cargo, gem"
run_table <<'CASES'
deny|cargo install ripgrep-all
pass|cargo install --path .
deny|cargo install -f wget
pass|cargo install -f jq
pass|cargo install jq@1.7
pass|cargo install --version 1.7 jq
deny|cargo install --git https://github.com/someone/sometool
pass|cargo install --git https://github.com/jqlang/jq.git
pass|cargo build
deny|gem install rails
pass|gem install jq -v 1.0
pass|gem list
CASES

echo "[8] claude mcp add"
run_table <<'CASES'
deny|claude mcp add --transport http sentry https://mcp.example.com/mcp
pass|claude mcp add --transport http github https://mcp.example.com/mcp
deny|claude mcp add foo -- npx -y some-pkg
pass|claude mcp add github -- npx -y some-pkg
pass|claude mcp add -e API_KEY=x -s user github -- npx -y some-pkg
pass|claude mcp list
pass|claude plugin list
pass|claude --version
CASES

echo "[9] where the install sits in the command line"
run_table <<'CASES'
deny|sudo brew install wget
deny|FOO=1 brew install wget
deny|cd /tmp && brew install wget
deny|true; brew install wget
deny|(brew install wget)
deny|brew install wget 2>/dev/null
deny|brew install wget > log.txt 2>&1
deny|brew install wget # needed for the build
pass|brew install jq 2>/dev/null
pass|brew install jq > log.txt 2>&1
pass|brew install jq # needed for the build
pass|brew install jq && echo done
deny|sh -c "brew install wget"
deny|bash -lc 'brew install wget'
pass|bash -lc 'brew install jq'
deny|env FOO=1 brew install wget
deny|echo "#x"; brew install wget
CASES

echo "[10] text that only mentions an install is not an install"
run_table <<'CASES'
pass|echo 'brew install wget'
pass|echo "run: npm install -g typescript"
pass|git commit -m "docs: brew install wget"
pass|grep -r "npm install -g" .
pass|printf '%s\n' "pip install --user requests" >> notes.md
pass|# brew install wget
CASES
expect pass "$(printf 'cat > notes.md <<EOF\nbrew install wget\nEOF')"
expect pass "$(printf "cat > notes.md <<'DOC'\nIt's simple: brew install wget\nDOC\necho done")"
expect deny "$(printf "bash <<'EOF'\nbrew install wget\nEOF")"
expect deny "$(printf 'echo start\nbrew install wget\necho end')"

echo "[11] ordinary commands pass and never prompt"
run_table <<'CASES'
pass|ls -la
pass|git status
pass|git log --oneline | head -5
pass|for f in *.md; do echo "$f"; done
pass|find . -name "*.py" | xargs grep -l "import"
pass|awk '{print $1}' file.txt
pass|echo "it's fine"
pass|python3 -c 'print("hi")'
pass|jq '.a | .b' x.json
pass|make test
pass|npm run build
pass|npm test -- --watch=false
pass|cargo test --all
pass|uv run pytest -q
pass|pip --version
pass|gem env
pass|docker compose up -d
pass|curl -fsSL https://example.com/x.json -o x.json
pass|sed -i '' 's/a/b/' file.txt
pass|if [ -f x ]; then cat x; fi
pass|echo "unterminated
CASES

echo "[12] when something is broken, it asks; it does not open"
expect ask 'brew install "unterminated'
mkdir -p "$TMP/crash" "$TMP/nopy" "$TMP/bin"
cp "$GATE" "$TMP/crash/gate.sh"; printf 'raise SystemExit(3)\n' > "$TMP/crash/gate.py"
expect ask "brew install jq" "$TMP/crash/gate.sh"
expect pass "ls -la" "$TMP/crash/gate.sh"
cp "$GATE" "$TMP/nopy/gate.sh"; cp "$ROOT/scripts/gate.py" "$TMP/nopy/gate.py"
for c in bash cat grep dirname; do p=$(command -v "$c") && ln -s "$p" "$TMP/bin/$c"; done
out=$(jq -cn '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"brew install jq"}}' | PATH="$TMP/bin" bash "$TMP/nopy/gate.sh" 2>/dev/null)
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "ask" ] && ok "ask  python3 missing, install command" || ng "python3 missing: did not ask"
out=$(jq -cn '{hook_event_name:"PreToolUse", tool_name:"Bash", tool_input:{command:"ls -la"}}' | PATH="$TMP/bin" bash "$TMP/nopy/gate.sh" 2>/dev/null)
[ -z "$out" ] && ok "pass python3 missing, ordinary command" || ng "python3 missing: ordinary command did not pass"
out=$(printf 'not json brew install wget' | bash "$GATE" 2>/dev/null)
[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision' 2>/dev/null)" = "ask" ] && ok "ask  hook input is not JSON" || ng "broken input: did not ask"

echo "[13] the two switches"
mkdir -p "$TMP/strict"; cp "$GATE" "$TMP/strict/gate.sh"
sed -e 's/^ASK_ON_LOW = False/ASK_ON_LOW = True/' -e 's/^GATE_ALL_PIP = False/GATE_ALL_PIP = True/' "$ROOT/scripts/gate.py" > "$TMP/strict/gate.py"
expect ask "brew install jq" "$TMP/strict/gate.sh"
expect deny "pip install requests" "$TMP/strict/gate.sh"
expect pass "pip install -r requirements.txt" "$TMP/strict/gate.sh"
expect deny "uv pip install ruff" "$TMP/strict/gate.sh"

echo "[14] the messages"
out=$(jq -cn --arg d "$PROJ" '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:"brew install evil/tap/jq"}}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GATE" 2>/dev/null)
r=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)
case "$r" in *"docs/tool-audits/evil-tap-jq-audit.md"*"/install-gate:tool-audit"*) ok "deny names the expected record file and the skill" ;; *) ng "deny message lacks the record path or the skill name" ;; esac
printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 && ok "output is a PreToolUse decision" || ng "output shape"
out=$(jq -cn --arg d "$PROJ" '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:"brew install ripgrep"}}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GATE" 2>/dev/null)
r=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null)
case "$r" in *"MID"*"docs/tool-audits/ripgrep-audit.md"*) ok "ask names the risk and the record" ;; *) ng "ask message lacks the risk or the record path" ;; esac
reason() { jq -cn --arg c "$1" --arg d "$PROJ" '{hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GATE" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null; }
case "$(reason 'brew install $PKG')" in *"installs something (brew), but the names are not in the command text"*"Check the command"*) ok "ask says the names are not in the command" ;; *) ng "ask message for an unreadable name" ;; esac
case "$(reason 'watch -n 5 brew install wget')" in *"looks like an install of wget (brew) inside a command the gate cannot fully read"*"no usable audit record"*) ok "ask names the tool found inside an unknown command" ;; *) ng "ask message for an install inside an unknown command" ;; esac
out=$(jq -cn --arg d "$PROJ" '{hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{content:"brew install wget"}}' | CLAUDE_PROJECT_DIR="$PROJ" bash "$GATE" 2>/dev/null)
[ -z "$out" ] && ok "tools other than Bash are ignored" || ng "reacted to a tool other than Bash"

echo "[15] shell syntax around the install: keywords, groups, substitutions, eval, wrappers"
run_table <<'CASES'
deny|if true; then brew install wget; fi
deny|if brew install wget; then echo ok; fi
deny|if false; then :; else brew install wget; fi
deny|for x in 1; do brew install wget; done
deny|while true; do brew install wget; break; done
deny|{ brew install wget; }
deny|! brew install wget
deny|time brew install wget
deny|time -p brew install wget
deny|echo `brew install wget`
deny|true && `brew install wget`
deny|x=`brew install wget`
deny|echo "$(brew install wget)"
deny|echo "now `brew install wget` runs"
deny|echo $(brew install wget)
deny|x=$(brew install wget)
deny|eval "brew install wget"
deny|eval brew install wget
deny|nice -n 5 brew install wget
deny|env -u FOO brew install wget
deny|timeout 60 brew install wget
deny|timeout -s KILL 60 brew install wget
deny|arch -arm64 brew install wget
deny|doas brew install wget
deny|command brew install wget
deny|exec brew install wget
deny|nohup brew install wget
deny|caffeinate -i brew install wget
deny|stdbuf -oL brew install wget
deny|false || brew install wget
deny|'brew' install wget
deny|"brew" install wget
deny|brew install "wget"
deny|ssh buildbox 'brew install wget'
deny|ssh -p 2222 me@buildbox brew install wget
deny|bash <<< "brew install wget"
deny|uv pip install --system requests
deny|uv pip install --break-system-packages requests
deny|sudo uv pip install requests
pass|if true; then brew install jq; fi
pass|{ brew install jq; }
pass|echo "$(brew install jq)"
pass|eval "brew install jq"
pass|nice -n 5 brew install jq
pass|timeout 60 brew install jq
pass|ssh buildbox 'brew install jq'
pass|uv pip install --system httpie
pass|uv pip install --system -r requirements.txt
pass|uv pip install requests
ask|if true; then brew install ripgrep; fi
ask|echo "$(brew install ripgrep)"
CASES
expect deny "$(printf 'brew install \\\n  wget')"
expect deny "$(printf 'brew \\\ninstall wget')"
expect pass "$(printf 'brew install \\\n  jq')"
expect deny "$(printf 'brew\tinstall wget')"

echo "[16] an install the gate cannot fully read asks; it does not pass"
run_table <<'CASES'
ask|echo wget | xargs brew install
ask|echo jq | xargs brew install
ask|cat tools.txt | xargs -n 1 brew install
ask|cat tools.txt | xargs npm install -g
ask|brew install $PKG
ask|brew install "$PKG"
ask|brew install $(cat tools.txt)
ask|for p in wget curl; do brew install $p; done
ask|watch -n 5 brew install wget
ask|echo "brew install wget" | sh
ask|printf 'brew install wget\n' | sudo bash
ask|echo brew install wget | bash
deny|eval eval brew install wget
ask|eval eval eval eval eval eval eval eval brew install wget
pass|watch -n 5 brew install jq
pass|echo "brew install jq" | sh
pass|echo "pip install requests" | bash
pass|cat tools.txt | xargs npm install
pass|cat reqs.txt | xargs pip install
CASES

echo "[17] the same syntax without an install still passes and never prompts"
run_table <<'CASES'
pass|echo '$(brew install wget)'
pass|echo 'run `brew install wget` first'
pass|echo "run \`brew install wget\` first"
pass|echo "run \$(brew install wget) first"
pass|git commit -m 'docs: use $(brew install wget)'
pass|echo brew install wget
pass|echo brew install wget >> notes.md
pass|for x in brew install wget; do echo "$x"; done
pass|grep -rn brew install .
pass|command -v brew
pass|which brew npm
pass|echo "$(date)"
pass|x=`date`
pass|echo "$(git rev-parse HEAD)" | cut -c1-7
pass|eval "$(ssh-agent -s)"
pass|ssh buildbox 'ls -la'
pass|ssh -p 2222 me@buildbox uptime
pass|time make test
pass|nice -n 5 make -j4
pass|timeout 60 npm test
pass|xargs -n 1 echo < list.txt
pass|{ echo a; echo b; }
pass|! grep -q x file.txt
pass|while read -r l; do echo "$l"; done < file.txt
pass|if brew list jq >/dev/null; then echo yes; fi
pass|cat file.txt | sh
pass|echo "ls -la" | bash
pass|bash <<< "ls -la"
pass|echo $((1 + 2))
pass|uv pip install -r requirements.txt
CASES
expect pass "$(printf 'ls \\\n  -la')"

echo "[18] what the gate does not see (the README lists these; they pass)"
run_table <<'CASES'
pass|python3 -c "import os; os.system('brew install wget')"
pass|node -e "require('child_process').execSync('brew install wget')"
pass|B=brew; $B install wget
pass|br''ew install wget
pass|bash ./setup.sh
pass|watch 'brew install wget'
pass|curl -fsSL https://example.com/install.sh | sh
pass|npx cowsay hi
pass|uvx ruff check
pass|go install example.com/tool@latest
pass|docker pull alpine
CASES

echo "[19] how live-check.sh tells \"the hook did not run\" from \"the hook ran and did not help\""
# Sample hook lines in the shape Claude Code writes them, not a real session (tests/hook-events-test.sh).
bash -n "$ROOT/tests/live-check.sh" 2>/dev/null && grep -q -- '--include-hook-events' "$ROOT/tests/live-check.sh" \
  && ok "live-check.sh parses and asks Claude Code for the hook lines" || ng "live-check.sh does not parse, or does not ask for the hook lines"
HE_OUT=$(bash "$ROOT/tests/hook-events-test.sh" 2>&1); HE_RC=$?
if [ "$HE_RC" = "0" ]; then ok "the three verdicts on sample hook lines: ran, failed to run, never started ($(printf '%s\n' "$HE_OUT" | grep -c '^  ok ') cases)"
else printf '%s\n' "$HE_OUT" | grep '^  FAIL ' | sed 's/^/  /'; ng "the three verdicts on sample hook lines (run tests/hook-events-test.sh to see all cases)"; fi

echo
echo "Result: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ] || exit 1
echo "The hook script decides correctly. To see whether Claude Code actually calls it, run tests/live-check.sh."
