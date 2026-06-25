# SysMoBench metric evaluation

This directory holds the model-quality evaluation of the FaB Paxos spec against the four SysMoBench metrics. SysMoBench itself scores AI-generated models over its own eleven systems (etcd Raft, ZooKeeper, and others), which is Variant B of the project. We wrote our model by hand and FaB is not one of its systems, so we apply its four metrics as a rubric, using the tools it wraps (SANY and TLC), and we report a verdict per metric rather than a single weighted score.

## Metrics and results

| Metric (weight) | Result | Evidence |
|---|---|---|
| Syntax (0.15) | pass | SANY parses all four modules; `Next` is nine named actions |
| Runtime (0.15) | pass | TLC checks 147,340 states with no runtime error; coverage below shows every action fires |
| Conformance (0.35) | not applicable | Variant A has no implementation, so there are no system traces to validate against |
| Invariant (0.35) | pass | CS1-CS3 (147,340 states), CL1-CL2 (4,642,112 states) |

## Runtime coverage

Command, from `spec/`:

```
java -jar ~/tools/tla2tools.jar -coverage 1 -workers 4 -config MCFaBPaxos.cfg MCFaBPaxos.tla
```

Raw log: `coverage.raw.txt`. Final cumulative per-action counts (distinct states generated : total invocations):

| Action | Distinct states | Invocations |
|---|---|---|
| LeaderPropose | 286 | 28,368 |
| Accept | 13,214 | 1,671,512 |
| Learn | 41,975 | 125,136 |
| LearnViaPull | 39,709 | 66,752 |
| SuspectLeader | 31,452 | 294,680 |
| LeaderChange | 51 | 1,290 |
| Query | 51 | 1,128 |
| Reply | 20,528 | 94,356 |
| ByzantinePropose | 72 | 28,160 |

Every action has a nonzero count, so the spec has no dead transitions. The recovery actions (LeaderChange, Query, ByzantinePropose) carry low counts because MaxPN = 1 bounds the model to a single leader change and one recovery term. They still fire, which is what the coverage check confirms.
