# Example execution traces

These are example runs of the Simplified FaB Paxos model.

## How the traces were produced

Each trace is TLC output, not hand-written. We run the **unmodified** protocol in `../FaBPaxos.tla` and add a read-only observer invariant (in `../MCFaBPaxosTrace.tla`) that says "the goal has not happened yet." TLC's breadth-first search returns the shortest run that reaches the goal, as a counterexample to the observer. The observer appears in no action, guard, or threshold, so the set of behaviors is exactly the protocol's; the printed run is faithful.

Each scenario has two files:

- `<name>.raw.txt` is the verbatim TLC stdout (banner, the observer violation, the state trace, and statistics).
- `<name>.txt` is a shorter version

The observer reports "Invariant ... is violated." That is the intended outcome: the violation is the witnessed execution, not a failure of the protocol.

## Scenarios

| Trace | Config | Shows |
|---|---|---|
| `common-case` | `common-case.cfg` | Leader proposes, a fast quorum of five acceptors accepts, a learner decides. One term, no faults. |
| `recovery` | `recovery.cfg` | Proposers suspect the leader, a new leader is elected at pn 1, queries acceptors, builds a progress certificate, proposes, and a learner decides at pn 1. |
| `byzantine` | `byzantine.cfg` | One Byzantine acceptor equivocates (votes both values). A learner still decides the correct value on a quorum of four correct acceptors plus the Byzantine vote; the conflicting vote forms no quorum. |

## Regenerating

Run from the `spec/` directory (the parent of this folder):

```
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/common-case.cfg MCFaBPaxosTrace.tla
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/recovery.cfg    MCFaBPaxosTrace.tla
java -jar ~/tools/tla2tools.jar -fp 1 -config traces/byzantine.cfg   MCFaBPaxosTrace.tla
```

## Counterexamples (broken variants, for the report's verification section)

These two files are different in kind from the traces above. They are executions of a **deliberately broken** version of the protocol, kept to show what our checks catch. Each was produced by editing `FaBPaxos.tla`, running the safety config (`MCFaBPaxos.cfg`), capturing the violation, then reverting the edit.

| File | Broken how | Shows |
|---|---|---|
| `mutation-cs3` | fast-learn quorum weakened from 5 to 4 | a learner decides a non-chosen value, CS3 fails, so the model detects real violations |
| `loadbearing-cs2` | acceptor `VouchedAtPN` check removed | the certificate is load-bearing: a Byzantine leader's poisonous write gets a second value chosen, CS2 fails |

The real spec (quorum 5, certificate check present) has neither violation. Each file pair is the verbatim TLC log (`.raw.txt`) and a captioned version (`.txt`).
