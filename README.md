# CS4720 Research Project - Simplified FaB Paxos in TLA+

TU Delft, CS4720 *Research in Program Analysis* (Spring 2026 / Q4) Project-A, Variant A (designing the TLA+ specification ourselves).

**Team-7**

Ion Tulei, Alexandru Verhovetchi

**System under analysis**: Fast Byzantine Consensus (FaB Paxos), a simplified subset.

**Source paper**: Martin, J.-P., & Alvisi, L. (2006). [*Fast Byzantine Consensus*](https://www.cs.utexas.edu/~lorenzo/papers/fab.pdf).

## Repository layout

```
.
├── README.md
├── .gitignore
├── docs/
└── spec/
    ├── FaBPaxos.tla                      (protocol module: state, actions, invariants)
    ├── MCFaBPaxos.tla / .cfg             (safety wrapper: CS1-CS3, symmetry, constraint)
    ├── MCFaBPaxosLiveness.tla / .cfg     (liveness wrapper: fairness, CL1, CL2)
    ├── MCFaBPaxosTrace.tla               (observer invariants for example traces)
    ├── traces/                           (example runs + two counterexamples, with README)
    ├── perf/                             (controlled performance study: configs, logs, README)
    └── eval/                             (SysMoBench metric evaluation: coverage log, README)
```

## Build

### Prerequisites

- **Java 11+** (TLA+ tooling requires a modern JVM)
- **`tla2tools.jar`** from the [TLA+ releases page](https://github.com/tlaplus/tlaplus/releases). Download once and place anywhere; the README assumes `~/tools/tla2tools.jar`.

```bash
mkdir -p ~/tools
curl -fL -o ~/tools/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
java -version   # should report 11 or higher
```

## Verification

Run everything from the `spec/` directory.

### Safety (invariants)

```bash
cd spec
java -jar ~/tools/tla2tools.jar -workers 4 -config MCFaBPaxos.cfg MCFaBPaxos.tla
```

Ends with `Model checking completed. No error has been found.` TLC checks these across every reachable state, at `f = 1` with the full per-class Byzantine threat (one Byzantine acceptor, proposer, and learner):

| Invariant | Meaning |
|---|---|
| `TypeOK` | All state variables remain well-typed |
| `CS1Inv` | Only a value that has been proposed may be chosen |
| `CS2Inv` | Only a single value may be chosen |
| `CS3Inv` | Only a chosen value may be learned by a correct learner |

#### A note on CS1 (validity)

CS1 says only a proposed value may be chosen. The paper means any proposer here, including a faulty one, not only a correct proposer. Three points support this reading.

1. The definition. Section 1 states CS1 as "only a value that has been proposed may be chosen", with no mention of a correct proposer.
2. The model. Section 3 lets each class hold up to `f` Byzantine agents, so a proposer, and the leader, can be Byzantine.
3. The proof. The Section 5.4 proof rests on the acceptors, not the proposer: correct acceptors accept only proposed values, so a chosen value was proposed. CS3 names a correct learner, but CS1 leaves the proposer unqualified.

A Byzantine leader that proposes one real value and gets it chosen does not break CS1.

Our `CS1Inv` follows this definition. It checks that a chosen `(value, pn)` has a matching `PROPOSE` in the message log, from any proposer:

```tla
CS1Inv ==
  \A v \in Value, pn \in PN :
    Chosen(v, pn) =>
      \E m \in msgs : m.type = "PROPOSE" /\ m.value = v /\ m.pn = pn
```

The `PROPOSE` record carries no proposer field, so the check treats a correct and a Byzantine proposer the same way, which matches the paper.

### Liveness (temporal properties)

```bash
java -jar ~/tools/tla2tools.jar -workers 4 -deadlock -lncheck final \
     -config MCFaBPaxosLiveness.cfg MCFaBPaxosLiveness.tla
```

Checks the two liveness properties under weak fairness and the paper's good-period assumption (a correct stable leader). `-deadlock` is required because the terminal "all learned" state has no successor.

| Property | Meaning |
|---|---|
| `CL1` | Some proposed value is eventually chosen |
| `CL2` | Once a value is chosen, every correct learner eventually learns it |

The liveness config drops `SYMMETRY` and the state `CONSTRAINT`, since both are unsound for liveness checking.

### Example execution traces

```bash
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/common-case.cfg MCFaBPaxosTrace.tla
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/recovery.cfg    MCFaBPaxosTrace.tla
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/byzantine.cfg   MCFaBPaxosTrace.tla
```

Each prints a short example run of the unmodified protocol (common case, recovery, and a tolerated Byzantine acceptor). The same folder also holds two counterexamples from broken variants, a weakened quorum and a removed certificate check, kept to show what the safety checks catch. See [`spec/traces/README.md`](./spec/traces/README.md) for what each file shows and how it is produced.

### Performance study

```bash
java -jar ~/tools/tla2tools.jar -workers 4 -config perf/<run>.cfg MCFaBPaxos.tla
```

We vary one parameter at a time from the safety baseline, holding `f = 1` and `MaxPN = 1`, and record states, depth, and runtime. The value domain is the main cost driver, and symmetry reduction is essential: with it the model is about 147k states, without it the run does not finish. The full run table and the command per run are in [`spec/perf/README.md`](./spec/perf/README.md).

### Model-quality evaluation (SysMoBench metrics)

```bash
java -jar ~/tools/tla2tools.jar -coverage 1 -workers 4 -config MCFaBPaxos.cfg MCFaBPaxos.tla
```

We score the model against the four SysMoBench metrics, applied as a rubric since SysMoBench targets AI-generated models over its own systems. The spec passes syntax, runtime, and invariant. Conformance does not apply, since we have no implementation to trace. The coverage run above confirms every action fires, so the spec has no dead transitions. See [`spec/eval/README.md`](./spec/eval/README.md).

## Model parameters

Set in [`spec/MCFaBPaxos.cfg`](./spec/MCFaBPaxos.cfg) (safety):

| Constant | Value | Meaning |
|---|---|---|
| `F` | 1 | Byzantine-fault budget |
| `Acceptors` / `ByzAcceptors` | `{a1..a6}` / `{a1}` | 5f+1 acceptors, one Byzantine |
| `Proposers` / `ByzProposers` | `{p1..p4}` / `{p1}` | 3f+1 proposers, one Byzantine (can become leader) |
| `Learners` / `ByzLearners` | `{l1..l4}` / `{l1}` | 3f+1 learners, one Byzantine |
| `Value` | `{v0, v1}` | Two candidate values (two are needed to make CS2 non-trivial) |
| `MaxPN` | 1 | Proposal numbers `0..1`, one leader change |

The liveness config differs where the analysis requires it: `ByzProposers = {}` (correct stable leader) and `Value = {v0}` (progress does not depend on the value count).

## Notes

- TLC writes a `states/` scratch directory while running; it is gitignored and safe to delete.
- The safety run at `MaxPN = 1` finishes in about ten minutes and explores ~147k states. We also ran `MaxPN = 2` (two leader changes); it explored 5.6M states in 5 hours with no violation but did not finish, so the checked-in config uses `MaxPN = 1`.
- The performance study is in `spec/perf/` and the SysMoBench metric evaluation in `spec/eval/`, each with its own README.
