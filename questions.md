# Open questions

## Blocking: how will optimized candidates be certified?

Decide this before building the optimization loop.

**Evidence (2026-11-22).** A hand-built eight-lane schedule,
`docs/candidates/matvec-grid-exchange-v1.json`, simulates in 79 cycles against
1,344 for the certified baseline and matches the reference on every fixture. It
cannot be accepted: the catalog takes only Lean terms carrying all-input proofs,
and nothing turns a candidate file into one. Today only serial one-lane
schedules have reusable proofs; the one certified parallel candidate, the
two-lane product pair, was proved by hand.

**Why hand proofs do not scale.**

- `Evaluation/Serial.lean` covers a single instruction in flight on lane 0.
- The only tool for overlapping instructions is `Evaluation.run_path`, with one
  lemma per boundary. The product pair (8 instructions, 20 boundaries across its
  two variants) takes about 460 lines.
- The 79-cycle schedule has 624 instructions, 80 boundaries and 272 symbolic
  inputs. A pipelined multi-lane proof library is an estimated 1–2k lines before
  the first candidate, and every later candidate still needs its own proof.

**What depends on the input.** Every legality rule is input-independent except
the arithmetic ranges, and every output is a polynomial in the inputs. One
symbolic run can therefore decide everything:

1. issue, pending, writeback, bank, address and initialization rules, from the
   schedule alone;
2. each register as a polynomial with an interval bound, checking the 16-bit
   and 48-bit rules;
3. each output polynomial against the reference polynomial.

**Recommended: a checker proved sound once.** Prove
`check candidate = true → ExecutionSafety ∧ FunctionalCorrectness` a single time.
Each candidate is then certified by evaluating `check`, with no per-candidate
proof. Estimated one-time cost: 1–2k lines, comparable to hand-proving one
parallel candidate.

**Alternatives.**

- A tactic that generates the per-boundary lemmas. It needs no soundness proof,
  but single-boundary lemmas on eight lanes already need raised heartbeat
  limits, so it would be slow and brittle.
- Agent-written proofs per candidate. This is closest to what TinyTPU studies,
  but proof effort would dominate the search budget on these workloads.

**Decisions still open.**

1. Range analysis. Intervals suffice for the matrix workloads, where only inputs
   are multiplied and sums of 16 products stay far inside 48 bits. They are
   conservative for correlated values such as `x * x ≥ 0`; the polynomial task
   in `PLAN.md` section 9 is chosen to expose this.
2. Each workload needs a one-time proof that its reference equals a normal-form
   polynomial.
3. What the experiment measures. With an automatic checker the agent writes no
   proofs, so the measurable quantity becomes "candidates that pass sampled
   inputs but fail certification", not proof effort. Confirm that this answers
   the question we care about.

**Acceptance test for whatever is chosen:** certify `matvec-grid-exchange-v1`
and reject single-instruction mutants of it.

Resolved decisions on proof evaluation, diagnostics and duplicate JSON keys are
recorded in [docs/decisions.md](docs/decisions.md).
