#!/usr/bin/env python3
"""Score a proposed COMMS protocol change against the fitness function.

  fitness = fewer tokens AND capability maintained-or-improved   (Roy, 2026-07-19)

Tokens are measurable. CAPABILITY IS NOT — and that asymmetry is the whole
danger: optimising only the measurable half yields compression that silently
loses meaning, which is precisely the false-green class this fleet spent
2026-07-19 killing (unwired scanner, mutation that did not apply, a regex that
could not match its own target).

So capability is scored ADVERSARIALLY, against required FACTS a message must
still carry. A proposal that drops a fact is REJECTED however many tokens it
saves. Token win is necessary, never sufficient.

Usage:
  comms-fitness.py score   --before F --after F --facts F
  comms-fitness.py tokens  "text"
  comms-fitness.py selftest

--facts: one required fact per line. Each MUST appear verbatim in the encoded
message (SHAs, file:line, counts, RFC keywords, verdicts). These are the things
a decoder must be able to recover; if an encoding cannot carry them it has lost
capability regardless of how it reads.
"""
import sys, json, pathlib

def _enc():
    try:
        import tiktoken
    except ImportError:
        sys.exit("tiktoken not installed: python3 -m venv .venv && .venv/bin/pip install tiktoken")
    return tiktoken.get_encoding("o200k_base")

def ntok(s: str) -> int:
    return len(_enc().encode(s))

# RFC 2119 polarity pairs, LONGEST FIRST. A negative is a DISTINCT fact from its
# positive, never a substring of it. Order matters: match "MUST NOT" before "MUST".
_NEGATIVES = ["MUST NOT", "SHALL NOT", "SHOULD NOT", "MAY NOT", "CANNOT"]

def _present(fact: str, text: str) -> bool:
    """Boundary-anchored containment.

    Plain `fact in text` was the defect hive found: facts are DECLARED as tokens
    but were MATCHED as unanchored substrings, so
      - "MUST" was satisfied by "MUST NOT"  (and vice versa: dropping NOT scored
        as capability-preserved, ADOPTing a REVERSED SAFETY DIRECTIVE at -37.5%)
      - "recipe.rs:1749" was satisfied by "recipe.rs:17490" (a WRONG file:line)
    Trailing boundary excludes ALPHANUMERICS ONLY — not ':'. Excluding ':' was an
    over-correction caught by regression: it broke the v2 cite anchor
    @repo@sha:path:line, where a path is LEGITIMATELY followed by ':' (facts_kept
    fell 4 -> 2 and a previously ADOPTED change flipped to REJECT). Excluding
    alphanumerics alone still blocks 1749 matching inside 17490, because the
    extending character is a digit.
    """
    import re
    pat = r"(?<![A-Za-z0-9_])" + re.escape(fact) + r"(?![A-Za-z0-9_])"
    return re.search(pat, text) is not None

def _polarity_flips(before: str, after: str) -> list[str]:
    """Compare the COUNT of RFC 2119 negatives, as a CLASS, before vs after.

    Checked INDEPENDENTLY of the facts list, because the caller cannot be relied
    on to declare "MUST NOT" as a fact — and the one time they forget is exactly
    when the tool would bless an inversion. This is the safety backstop.

    COUNTED, not membership-tested (hive, 2026-07-19). The first fix moved the
    defect from substring-blind to COUNT-blind:
        before "=MUST NOT flash and MUST NOT push @d4c65886"
        after  "=MUST NOT flash @d4c65886"
        => "MUST NOT" still present, verdict ADOPT, one obligation SILENTLY GONE
    Live, not theoretical — fleet messages routinely carry several obligations.

    Counted as a CLASS TOTAL, not per keyword, which also fixes the precision
    cost hive flagged: MUST NOT -> SHALL NOT is a legal RFC 2119 synonym swap
    and MUST NOT be rejected. A scorer that rejects legal rewrites gets routed
    around — the same crying-wolf failure we warned specs about on credentials.
    """
    nb = sum(before.count(n) for n in _NEGATIVES)
    na = sum(after.count(n) for n in _NEGATIVES)
    if na < nb:
        return [f"{nb} negative obligation(s) before, {na} after"]
    return []

def score(before: str, after: str, facts: list[str]) -> dict:
    tb, ta = ntok(before), ntok(after)
    lost = [f for f in facts if f and not _present(f, after)]
    flips = _polarity_flips(before, after)
    lost = lost + [f"POLARITY: '{n}' dropped" for n in flips]
    kept = len(facts) - len([f for f in facts if f and not _present(f, after)])
    delta = ta - tb
    pct = (delta / tb * 100) if tb else 0.0
    # VERDICT: capability is a gate, not a term. No trade-off is offered,
    # because a token budget will always argue for dropping "one small fact".
    if lost:
        verdict = "REJECT — capability LOST"
    elif delta >= 0:
        verdict = "REJECT — no token saving"
    else:
        verdict = "ADOPT"
    return {
        "tokens_before": tb, "tokens_after": ta,
        "delta": delta, "pct": round(pct, 1),
        "facts_required": len(facts), "facts_kept": kept,
        "facts_lost": lost, "verdict": verdict,
    }

def selftest() -> int:
    """Negative controls. An unfired gate is not evidence — prove each REJECT fires."""
    facts = ["recipe.rs:1749", "MUST", "d4c65886"]
    cases = [
        ("lossy compression must be rejected",
         "the gate at recipe.rs:1749 MUST refuse sha d4c65886",
         "gate MUST refuse",                      "REJECT — capability LOST"),
        ("bloat must be rejected",
         "recipe.rs:1749 MUST d4c65886",
         "the gate located at recipe.rs:1749 MUST refuse the artifact d4c65886 without exception",
                                                  "REJECT — no token saving"),
        ("genuine win must be adopted",
         "The gate that is located at recipe.rs:1749 MUST refuse the artifact whose hash is d4c65886",
         "@recipe.rs:1749 =MUST refuse d4c65886", "ADOPT"),
        # --- hive 2026-07-19: the predicate could not see the failure it exists to catch ---
        ("SAFETY INVERSION must be rejected (hive probe A)",
         "=MUST NOT flash board B without the Roy gate @d4c65886",
         "=MUST flash B @d4c65886",               "REJECT — capability LOST"),
        ("wrong file:line must not score as kept (hive probe B)",
         "the gate at recipe.rs:1749 MUST refuse d4c65886 now",
         "@recipe.rs:17490 =MUST d4c65886",       "REJECT — capability LOST"),
        ("negative kept is still adoptable",
         "The gate at recipe.rs:1749 MUST NOT accept the artifact d4c65886 under any circumstance",
         "@recipe.rs:1749 =MUST NOT accept d4c65886", "ADOPT"),
        # --- hive round 2: presence-based polarity was COUNT-BLIND ---
        ("dropping ONE of TWO negatives must be rejected (hive probe H)",
         "=MUST NOT flash and MUST NOT push @d4c65886",
         "=MUST NOT flash @d4c65886",             "REJECT — capability LOST"),
        # facts overridden per-case: the shared list cites recipe.rs/MUST, neither
        # of which appears here. A control failing on its own harness is a harness
        # defect, not a finding — caught by running it rather than assuming.
        ("legal RFC 2119 synonym swap MUST NOT be rejected (hive probe G)",
         "The operator MUST NOT flash board B @d4c65886 before the gate",
         "=SHALL NOT flash B @d4c65886",          "ADOPT", ["d4c65886"]),
    ]
    fails = 0
    for case in cases:
        name, b, a, want = case[:4]
        case_facts = case[4] if len(case) > 4 else facts
        got = score(b, a, case_facts)["verdict"]
        ok = got == want
        fails += not ok
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}\n         want={want!r}\n          got={got!r}")
    print(f"\n{'ALL CONTROLS FIRED' if not fails else f'{fails} CONTROL(S) DID NOT FIRE'}")
    return 1 if fails else 0

def main() -> int:
    a = sys.argv[1:]
    if not a: sys.exit(__doc__)
    if a[0] == "tokens":
        print(ntok(a[1])); return 0
    if a[0] == "selftest":
        return selftest()
    if a[0] == "score":
        g = lambda f: pathlib.Path(a[a.index(f) + 1]).read_text()
        facts = [l.strip() for l in g("--facts").splitlines() if l.strip()]
        print(json.dumps(score(g("--before"), g("--after"), facts), indent=2))
        return 0
    sys.exit(__doc__)

if __name__ == "__main__":
    sys.exit(main())
