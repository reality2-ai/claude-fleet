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

def score(before: str, after: str, facts: list[str]) -> dict:
    tb, ta = ntok(before), ntok(after)
    lost = [f for f in facts if f and f not in after]
    kept = len(facts) - len(lost)
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
    ]
    fails = 0
    for name, b, a, want in cases:
        got = score(b, a, facts)["verdict"]
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
