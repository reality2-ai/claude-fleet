#!/usr/bin/env bash
# commit-msg-trailer.sh — KATs for the session-trailer hook (fleet task #119).
#
# THE POINT OF THIS SUITE IS THE REAL COMMIT PATHS, NOT THE HOOK IN ISOLATION.
# The defect being fixed is that `-m` and `-F` bypass the commit TEMPLATE, so a
# suite that only calls the hook with a hand-written file would pass while the
# actual bug survived untouched. Every ALLOW case below runs a real `git commit`
# in a throwaway repo and then reads the resulting commit message back.
#
# Both directions are asserted. A hook that stamps a trailer onto everything
# would pass a suite that only checked "the trailer is present", so the cases
# that must NOT be modified carry as much weight as the ones that must.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
HOOK="$PWD/hooks/git/commit-msg"

[[ -f "$HOOK" ]] || { echo "✗ FAIL: $HOOK missing"; exit 1; }
bash -n "$HOOK" || { echo "✗ FAIL: $HOOK has a syntax error"; exit 1; }

WS="$(mktemp -d)"; trap 'rm -rf "$WS"' EXIT
export CLAUDE_SESSION_URL="https://claude.ai/code/session_01TEST"
export CLAUDE_COAUTHOR="Claude Opus 4.8 <noreply@anthropic.com>"

fail=0; n=0
newrepo() {
  rm -rf "$WS/r"; mkdir -p "$WS/r"; git -C "$WS/r" init -q
  git -C "$WS/r" config user.email t@t.invalid; git -C "$WS/r" config user.name t
  mkdir -p "$WS/r/.git/hooks"; cp "$HOOK" "$WS/r/.git/hooks/commit-msg"
  chmod +x "$WS/r/.git/hooks/commit-msg"
  printf 'x\n' > "$WS/r/f"; git -C "$WS/r" add f
}
body() { git -C "$WS/r" log -1 --format=%B; }

check() {   # check <want: has|hasnot> <label> <predicate-on-body>
  local want="$1" label="$2" pat="$3" got
  n=$((n+1))
  if body | grep -Eq "$pat"; then got=has; else got=hasnot; fi
  if [[ "$got" == "$want" ]]; then printf '  ok   %-6s %s\n' "$got" "$label"
  else printf '✗ FAIL want=%-6s got=%-6s %s\n' "$want" "$got" "$label"; fail=$((fail+1)); fi
}

SESS='^Claude-Session: https://claude\.ai/code/session_01TEST$'
COAU='^Co-Authored-By: Claude Opus 4\.8 <noreply@anthropic\.com>$'

echo "── THE DEFECT ITSELF: -m and -F bypass the template ──"
newrepo; git -C "$WS/r" commit -q -m "feat: via dash-m"
check has "-m commit gets the session trailer" "$SESS"
check has "-m commit gets the co-author"       "$COAU"

newrepo; printf 'feat: via dash-F\n' > "$WS/msg"; git -C "$WS/r" commit -q -F "$WS/msg"
check has "-F commit gets the session trailer" "$SESS"

echo "── IDEMPOTENCE: an existing trailer must not be duplicated ──"
newrepo
git -C "$WS/r" commit -q -m "feat: already tagged

Claude-Session: https://claude.ai/code/session_01TEST"
n=$((n+1))
c="$(body | grep -c 'Claude-Session:')"
if [[ "$c" == 1 ]]; then printf '  ok   %-6s %s\n' "1x" "no duplicate session line"
else printf '✗ FAIL want=1 got=%s duplicate session line\n' "$c"; fail=$((fail+1)); fi

echo "── ANCHOR PLUS PAYLOAD: prose about the rule is NOT a trailer ──"
# android measured this: a body line beginning with the literal 'Claude-Session:' —
# its own prose describing the rule — satisfied a bare '^Claude-Session:' test, so
# the anchored and unanchored counts differed by ZERO while both were poisoned.
newrepo
git -C "$WS/r" commit -q -m "docs: describe the rule

Claude-Session:, never a bare occurrence in a body."
check has "prose mentioning the anchor still GETS a real trailer" "$SESS"

echo "── MUST NOT MODIFY ──"
newrepo; FLEET_SKIP_TRAILER=1 git -C "$WS/r" commit -q -m "chore: opted out"
check hasnot "FLEET_SKIP_TRAILER=1 leaves the message alone" "$SESS"

newrepo
n=$((n+1))
if env -u CLAUDE_SESSION_URL -u CLAUDE_COAUTHOR \
     git -C "$WS/r" commit -q -m "chore: no identity in env" 2>/dev/null; then
  if body | grep -Eq 'Claude-Session|Co-Authored-By'; then
    printf '✗ FAIL absent identity FABRICATED a trailer\n'; fail=$((fail+1))
  else printf '  ok   %-6s %s\n' "hasnot" "absent identity writes NOTHING (no placeholder)"; fi
else printf '✗ FAIL commit refused when identity absent — hook must never block\n'; fail=$((fail+1)); fi

echo "── MUST NEVER BLOCK A COMMIT ──"
# The hook's one hard requirement. Every path exits 0; an empty message is still
# refused by GIT (which is correct and is git's job), never by us.
newrepo
n=$((n+1))
out="$(git -C "$WS/r" commit -q -m "feat: normal" 2>&1)"; rc=$?
if (( rc == 0 )); then printf '  ok   %-6s %s\n' "exit0" "a normal commit succeeds"
else printf '✗ FAIL hook blocked a normal commit: %s\n' "${out:0:80}"; fail=$((fail+1)); fi

# A message that is only comments: git aborts it. Assert the hook did not turn it
# into a commit whose entire content is our trailer.
newrepo
n=$((n+1))
printf '# only a comment\n' > "$WS/msg2"
git -C "$WS/r" commit -q -F "$WS/msg2" >/dev/null 2>&1
if git -C "$WS/r" rev-parse HEAD >/dev/null 2>&1; then
  if ! body | grep -qvE '^$|Claude-Session|Co-Authored-By'; then
    printf '✗ FAIL a comment-only message became a trailer-only commit\n'; fail=$((fail+1))
  else printf '  ok   %-6s %s\n' "safe" "comment-only message did not become a trailer-only commit"; fi
else printf '  ok   %-6s %s\n' "safe" "comment-only message produced no commit (git refused, as it should)"; fi

echo
if (( fail )); then echo "✗ commit-msg-trailer: $((n-fail))/$n pass, $fail FAIL"; exit 1; fi
echo "✓ commit-msg-trailer: $n/$n pass"
