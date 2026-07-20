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
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
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

echo "── #88 (a) READ-ONLY LOOKUP — a lookup runs NOTHING ──"
# DEFECT 2026-07-20. `command` is in the wrapper list — correctly, because
# `command <flasher> …` really does invoke one and must not escape the gate. But
# that put `command -v <flasher>` — a pure "is it installed?" query that executes
# nothing — through the same token scan, and it DENIED.
#
# Third instance of the shape this file already carries two lessons about: the gate
# matched the VOCABULARY, not the ACT (cf. the openssl `-signature` contains `-sign`
# defect). Impact was the same both times and it is the expensive kind — it blocked
# hive's escalation TO the supervisor, then the supervisor's own artifact-sha
# pre-flight, then the attempt to write THIS TEST. A gate whose false positives
# block the verification that PRECEDES the dangerous act degrades the evidence base
# it exists to protect.
check pass 'command -v espflash'
check pass 'command -v esptool.py || echo ABSENT'
check pass 'type -p nrfjprog'
check pass 'which espflash'
check pass 'command -v espflash; sha256sum firmware.elf'
# …and the narrowing MUST hold. No lookup flag = a real invocation, still gated.
check deny 'command espflash flash --port /dev/ttyACM3 fw.elf'
check deny 'timeout 60 espflash flash --port /dev/ttyACM3 fw.elf'

echo "── #88 (b) PER-OPERATION AUTHORIZATION — deny stays the default ──"
# Before this, the only way past the gate was FLEET_FIRMWARE_GATE=off: blanket,
# permanent, silent, no record of what ran or on whose say-so. A gate whose sole
# escape hatch is "turn it off" gets turned off the first time it is inconvenient
# and never fires again.
#
# ★ WHAT THESE KATs DO AND DO NOT PROVE. They prove the grant is SPECIFIC (one
# artifact, one target), EXPIRING, and FAIL-CLOSED on every malformed shape. They do
# NOT prove a boundary against a determined agent — any process that reads the file
# can write it. The human remains the boundary; this converts a global off-switch
# into a dated, artifact-named, auditable record. Asserting more than that would be
# the decorative-gate defect this suite exists to catch.
AUTH="$WS/.fleet/flash-authorization"
FLASHCMD='cd ~ && espflash flash --chip esp32s3 --partition-table partitions.csv --port /dev/ttyACM3 r2-dfr1195-SENSOR-fakesensor-ble.elf'
NOW="$(date +%s)"

rm -f "$AUTH"
check deny "$FLASHCMD"                                    # no grant at all

grant() {   # expires artifact target
  printf 'expires=%s\nartifact=%s\ntarget=%s\nsha256=130dc6de\n' "$1" "$2" "$3" > "$AUTH"
}

grant "$((NOW + 900))" 'r2-dfr1195-SENSOR-fakesensor-ble.elf' '/dev/ttyACM3'
check pass "$FLASHCMD"                                    # live + matching → allow

grant "$((NOW - 60))"  'r2-dfr1195-SENSOR-fakesensor-ble.elf' '/dev/ttyACM3'
check deny "$FLASHCMD"                                    # EXPIRED — no standing off-switch

grant "$((NOW + 900))" 'some-other-image.elf'             '/dev/ttyACM3'
check deny "$FLASHCMD"                                    # wrong artifact — one op, not a class

# Right image, WRONG BOARD is precisely the mis-flash that bricked D4. A grant for
# one port must never authorize another.
grant "$((NOW + 900))" 'r2-dfr1195-SENSOR-fakesensor-ble.elf' '/dev/ttyACM0'
check deny "$FLASHCMD"

# PARTIAL records must authorize NOTHING. An empty artifact or target would
# substring-match every command — a half-written grant failing OPEN would be worse
# than no mechanism at all.
printf 'expires=%s\nartifact=\ntarget=\n' "$((NOW + 900))" > "$AUTH"
check deny "$FLASHCMD"
printf 'artifact=r2-dfr1195-SENSOR-fakesensor-ble.elf\ntarget=/dev/ttyACM3\n' > "$AUTH"
check deny "$FLASHCMD"                                    # no expiry = no grant
printf 'expires=never\nartifact=r2-dfr1195-SENSOR-fakesensor-ble.elf\ntarget=/dev/ttyACM3\n' > "$AUTH"
check deny "$FLASHCMD"                                    # unevaluable window = deny

# A live grant for one operation must not carry an UNRELATED one through.
grant "$((NOW + 900))" 'r2-dfr1195-SENSOR-fakesensor-ble.elf' '/dev/ttyACM3'
check deny 'nrfjprog --program other.hex --chiperase'
check deny 'composer ota sign --key k.pem fw.bin'
rm -f "$AUTH"

echo "── (3) HEREDOC BODIES ARE DATA, NOT COMMANDS (found 2026-07-20) ──"
# Defect (1) taught the splitter that text inside '…'/"…" is DATA. That lesson was
# never carried to the OTHER shell construct that carries a document. A ';' inside a
# heredoc BODY split the command, the next fragment began with a flasher name, and the
# gate hard-DENIED one `cat` writing one markdown file, touching no device.
#
# Same landing place as defect (1): the gate blocked the document that quotes the
# dangerous invocation IN ORDER TO WARN AGAINST IT. A gate whose false positives block
# the DOCUMENTATION of its own hazard is the cousin of one that blocks remediation.
#
# BOTH DIRECTIONS, because a fix that only makes things pass is worse than the defect:
# the body is skipped, and scanning RESUMES after the terminator.
check pass "$(printf 'cat > SAFETY.md <<EOF\nWrong: cd staged; espflash flash --partition-table p.csv\nEOF\n')"
check pass "$(printf 'cat <<EOF > notes.md\nnrfjprog --program x.hex --chiperase; never do this\nEOF\n')"
check pass "$(printf 'cat <<-EOF > n.md\n\tcomposer ota sign --key k.pem fw.bin; prose\n\tEOF\n')"
check pass "$(printf 'cat <<%s > n.md\nespflash flash t.bin; quoted delimiter\nEOF\n' "'EOF'")"
# LAUNDERING — a real op chained AFTER the terminator is still a real op.
check deny "$(printf 'cat > SAFETY.md <<EOF\nprose only\nEOF\nespflash flash --monitor t.bin\n')"
check deny "$(printf 'cat <<EOF > n.md\nprose\nEOF\nnrfjprog --program other.hex --chiperase\n')"
# `<<<` is a here-STRING, not a here-doc: it must not swallow the rest of the command.
check deny 'grep -q x <<< "text"; espflash flash --monitor t.bin'
# An UNTERMINATED heredoc consumes the rest as body — nothing after it is a command,
# and the shell would never run one either. Asserted so the -1/n branch stays covered.
check pass "$(printf 'cat > n.md <<EOF\nespflash flash t.bin\n')"

echo
if (( fail )); then echo "✗ firmware-gate: $((n-fail))/$n pass, $fail FAIL"; exit 1; fi
echo "✓ firmware-gate: $n/$n pass"
