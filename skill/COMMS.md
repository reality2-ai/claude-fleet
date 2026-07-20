COMMS_VERSION: 19

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
falsifier. Cite a commit when lines may move. Relayed requirements name their source.

Ground truth beats memory, transcript, and peer assertion. Before reporting a gate or
scanner result, verify its caller, input denominator, and a negative control that fails.
A clean unwired or empty scan is not evidence. Findings include severity, reproduction,
and the smallest fix or test. If no attack survives, report checks run and the strongest
untested attack.

Do not debate after evidence resolves the question. Record durable state in the repo or
decision ledger, then converge.
