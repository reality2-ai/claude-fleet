COMMS_VERSION: 22

# Fleet peer communication

Applies to agent-to-agent messages. Human reports and durable docs stay clear prose.

Send the shortest message that preserves the evidence and required action. Routine
target: 600 characters or less. No greeting, restatement, narration, raw-log dump, or
speculative finding list.

Optional dense form:

- `!` finding or falsifier
- `@` evidence: repo, commit, path:line, exact error, value, or test result
- `=` required action; use MUST/MUST NOT only for a real obligation
- `?` smallest unresolved question and decision owner
- `#` status: OPEN, HELD, CONFIRMED, REFUTED, DONE
- `~` non-binding information

One claim per line. Never shorten code, SHAs, paths, errors, values, units, or the
falsifier. Relayed requirements name their source.

Every `path:line` citation names the **branch AND the sha** it was read at. A branch alone
is not enough: line numbers are revision-scoped and move within a branch between reads. A
path alone is worse — the same path is an 83-line file on one branch and 10k+ on another.
Verifying one property of a revision (its length, its tip) does not validate another (its
line numbers); measure the property you are about to claim.

NEVER put a backtick or `$(...)` in a message passed through a shell tool. The shell
executes it before the message is sent: your text arrives mangled, words vanish
mid-sentence, and arbitrary commands run. Cite `feature`/`symbol` names bare, or quote
with single quotes. Two lanes have lost claims this way — a mangled message reads as a
sloppy peer, not as a tooling fault, so the reader draws the wrong conclusion.

Ground truth beats memory, transcript, and peer assertion. Before reporting a gate or
scanner result, verify its caller, input denominator, and a negative control that fails.
A clean unwired or empty scan is not evidence. Findings include severity, reproduction,
and the smallest fix or test. If no attack survives, report checks run and the strongest
untested attack.

Before edits, read repo `AGENTS.md` and `DECISIONS.md`. Before commit, append any key
ruling, review, or consequential delegated choice; routine commits state
`Decision-Log: none`. Do not debate after evidence resolves the question. Record durable
state, then converge.
