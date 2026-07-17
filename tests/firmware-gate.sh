#!/usr/bin/env bash
# firmware-gate.sh — regression guard for the auto-approve firmware/key gate (#88).
#
# TWO DEFECTS, FOUND 2026-07-17, BOTH IN hs_bash. They point opposite ways, which is
# why the KAT below asserts BOTH directions on every run:
#
#   (1) FALSE POSITIVE — the gate matched WORDS, not ACTS. The splitter was
#       `${c//&&/;}` + split-on-';': QUOTE-BLIND. Text inside '…'/"…" is DATA, but it
#       was fragmented anyway and each fragment classified AS IF IT WERE A COMMAND.
#       Ground truth, reproduced live:
#         git commit -m "a; write-persona is the wrong verb"   -> hard DENY
#         cd /x && fleet send hive "a; write-persona is wrong"  -> hard DENY
#       The `fleet send` exemption was also POSITION-BOUND (read only token 0 of the
#       WHOLE command), so any wrapper — `cd … &&`, `timeout 30 …` — defeated it.
#       IMPACT: blocked three lanes in one evening, including a RESUME.md commit (the
#       DURABLE HANDOFF RECORD) and a lane escalating a security finding TO the
#       supervisor. A gate that taxes precise reporting of a defect degrades the
#       evidence base it exists to protect, and teaches lanes to describe findings
#       vaguely to get them through. Cousin of the rule already banked in
#       hooks/git/pre-push: a gate whose false positives block REMEDIATION is worse
#       than no gate at that moment.
#
#   (2) FALSE NEGATIVE — the gate's HEADLINE VERB NEVER FIRED. The old test was
#         case " $seg " in *' ota '*' sign'*)
#       which CANNOT match `composer ota sign`, the exact canonical form it names:
#       matching `' ota '` consumes the space that `' sign'` then requires, so only the
#       non-adjacent `ota --foo sign` ever matched. Same for `' ota '*' push'`. Every
#       green run "confirmed" a check that was STRUCTURALLY INCAPABLE of firing.
#       This is task #89's decorative-cert defect one level up, in the gate itself:
#       an artifact that parses, reports OK, and verifies nothing. Found only by
#       writing POSITIVE controls for defect (1)'s fix — the fix's own tests were all
#       green while the gate denied NOTHING AT ALL (a `set -u` abort → silent
#       fail-open, also caught here and asserted against below).
#
# THE RULE BOTH DEFECTS EARN: a gate reporting OK is not evidence until its KATs prove
# it catches the thing. Assert the DENY direction and the ALLOW direction together —
# a suite that only proves false positives are gone cannot tell a working gate from a
# gate that was accidentally disabled.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
HOOK="$PWD/hooks/auto-approve.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }
bash -n "$HOOK" || { echo "✗ FAIL: $HOOK has a syntax error"; exit 1; }

# The hook only acts inside a .fleet workspace → build a throwaway one.
WS="$(mktemp -d)"; mkdir -p "$WS/.fleet"
trap 'rm -rf "$WS"' EXIT

fail=0; n=0

decide() {   # -> deny | allow | silent   (silent = falls through to a human prompt)
  local out d
  out="$(jq -nc --arg c "$1" --arg cwd "$WS" \
    '{tool_name:"Bash",cwd:$cwd,hook_event_name:"PreToolUse",tool_input:{command:$c}}' \
    | timeout 10 bash "$HOOK" 2>&1)"
  # a crashed hook (set -u abort, syntax error) emits no decision and FAILS OPEN —
  # that is the silent-disable mode this suite exists to catch, so surface it loudly.
  case "$out" in *'unbound variable'*|*'syntax error'*|*'command not found'*)
    printf '%s' "CRASH:${out:0:60}"; return ;; esac
  d="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "silent"' 2>/dev/null)"
  printf '%s' "${d:-silent}"
}

# want=deny  → a REAL flash/sign/mint op; must be denied (positive control)
# want=pass  → PROSE describing that work; must NOT be denied (negative control)
check() {
  local want="$1" c="$2" got d
  n=$((n+1)); d="$(decide "$c")"
  if [[ "$want" == deny ]]; then got="$d"; else [[ "$d" == deny ]] && got=deny || got=pass; fi
  if [[ "$got" == "$want" ]]; then printf '  ok   %-6s %s\n' "$d" "${c:0:72}"
  else printf '✗ FAIL want=%-5s got=%-8s %s\n' "$want" "$d" "${c:0:72}"; fail=$((fail+1)); fi
}

echo "── PROSE ABOUT THE WORK — must never be denied (defect 1) ──"
check pass 'cd /x && fleet send supervisor "a; write-persona is the wrong verb"'
check pass 'timeout 30 fleet send supervisor "a; write-persona is the wrong verb"'
check pass 'fleet send supervisor "a; write-persona is the wrong verb"'
check pass 'fleet broadcast "a; write-persona is the wrong verb"'
check pass 'fleet pair-send hive "mint cert; ota sign; write-persona — all prose"'
check pass 'cd /x && git commit -m "a; write-persona is the wrong verb"'
check pass 'git commit -m "a; write-persona is the wrong verb"'
check pass 'git commit -am "fix; mint cert handling in the stub"'
check pass 'cd /x && git commit -m "note: provision write path; see RESUME"'
check pass 'git commit -m "docs: record that we never mint-cert here"'
check pass 'cd /r2-specifications && git add RESUME.md && git commit -m "ruling: role=Member; no write-persona path exists"'
# PROSE QUOTING PROSE — the shape that denied this fix's own announcement broadcast.
# A \" inside "…" is an ESCAPED quote, not a closing one; reading it as closing falls
# out of the quoted region and splits the rest on ';'. Missing from the first KAT: it
# covered prose containing ';' but never prose containing an escaped quote.
check pass 'fleet broadcast "reproduced: git commit -m \"a; write-persona is wrong\" -> DENY"'
check pass "fleet send hive 'it said \"a; ota sign\" and that was prose'"
check pass 'git commit -m "quote the report: \"a; mint cert\" was never an op"'

echo "── VERIFYING IS NOT SIGNING — read-only crypto must never be denied (defect 4) ──"
# The gate blocked a read-only cert verify: `dgst` matched, AND `-signature`
# contains `-sign`, so the sign-detector matched its own opposite. Blocking a
# verify does not prevent a risky action — it prevents the evidence that would
# tell us whether the action is risky. Measured cost: it turned an
# independently-verified artifact into a singly-verified one.
check pass 'openssl dgst -sha256 -verify pub.pem -signature sig.bin persona.bin'
check pass 'openssl pkeyutl -verify -pubin -inkey pub.pem -sigfile sig.bin -in digest.bin'
check pass 'openssl x509 -in cert.pem -noout -text'
check pass 'openssl verify -CAfile ca.pem cert.pem'
check pass 'openssl asn1parse -in persona.der -inform DER'
check pass 'openssl dgst -sha256 persona.bin'

echo "── REAL OPS — must always be denied (positive controls; defect 2) ──"
# ...and the same subcommands when they actually SIGN or MINT.
check deny 'openssl dgst -sha256 -sign key.pem -out sig.bin persona.bin'
check deny 'openssl pkeyutl -sign -inkey key.pem -in digest.bin -out sig.bin'
check deny 'openssl x509 -req -in csr.pem -signkey ca.key -out cert.pem'
check deny 'openssl req -new -newkey ed25519 -keyout tg.key -out tg.csr'
check deny 'adafruit-nrfutil dfu serial -pkg x.zip -p /dev/ttyACM0 -b 115200 -sb'
check deny 'espflash flash --monitor target/x.bin'
check deny 'cd /tmp && sudo openssl genpkey -algorithm ed25519 -out tg.key'
check deny 'timeout 60 espflash flash x.bin'
check deny 'env FOO=1 dfu-util -a 0 -D fw.bin'
check deny 'probe-rs download --chip nRF52840 fw.elf'
check deny 'cargo embed --release'
check deny 'composer write-persona --out p.bin'
# the two that NEVER fired before 2026-07-17 — the whole reason this file exists
check deny 'composer ota sign --key k.pem fw.bin'
check deny 'composer ota push --target rak fw.bin'

echo "── LAUNDERING — an exemption must not carry a real op through ──"
check deny 'git commit -m "wip" && espflash flash --monitor t.bin'
check deny 'fleet send hive "ok" && espflash flash --monitor t.bin'
check deny 'git commit -m "a; b" ; adafruit-nrfutil dfu serial -pkg x.zip -p /dev/ttyACM0'
check deny 'fleet send hive "$(espflash flash t.bin)"'

echo
if (( fail )); then echo "✗ firmware-gate: $((n-fail))/$n pass, $fail FAIL"; exit 1; fi
echo "✓ firmware-gate: $n/$n pass"
