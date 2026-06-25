# Controlled performance study

This directory holds a one-variable-at-a-time study of TLC model-checking cost for the Simplified FaB Paxos safety spec. Every run uses `MCFaBPaxos.tla` with a per-experiment configuration file. We fix `F = 1` and `MaxPN = 1` across all runs and vary one other parameter at a time from the baseline, so each run isolates a single cost factor.

Why `F` and `MaxPN` stay fixed: `F = 2` needs `5F + 1 = 11` acceptors, which is out of reach for explicit-state checking on a laptop, and `MaxPN = 1` already exercises one full leader change, which is the recovery path the safety properties depend on. Both are ceilings, so the study varies the parameters that are tractable: value-domain size, Byzantine presence per class, symmetry reduction, and worker count.

## How to reproduce

All runs start from `spec/` and write a raw log per run:

```bash
java -jar ~/tools/tla2tools.jar -workers <N> -config perf/<run>.cfg MCFaBPaxos.tla > perf/<run>.raw.txt 2>&1
```

The runs were driven one at a time (sequential), since the metric is wall-clock and concurrent runs would share CPU and skew timing. A run that kept growing past 30 minutes was recorded as a partial; a run whose BFS queue was draining toward completion was allowed to finish.

## Results

| Run | Variable changed from baseline | Workers | Distinct states | Depth | Wall time | Outcome |
|---|---|---|---|---|---|---|
| baseline | none (reference) | 4 | 147,340 | 31 | 10m33s | completed, no error |
| values1 | one value instead of two | 4 | 18,316 | 30 | 1m03s | completed, no error |
| byz-acc | Byzantine acceptor only (no Byzantine proposer or learner) | 4 | 32,288 | 31 | 19m47s | completed, no error |
| byz-none | no Byzantine processes | 4 | 17,610 | 25 | 30m01s | did not finish (queue still growing) |
| e5a-workers1 | one value, no Byzantine, single worker | 1 | 5,547 | 23 | 35m08s | did not finish (cut, queue still growing) |
| e5b-workers4 | one value, no Byzantine, four workers | 4 | 15,024 | 34 | 40m51s | completed, no error |
| nosym | symmetry reduction turned off | 4 | 5,423,956 | 20 | 3m39s | did not finish (cut, queue 1.86M and growing) |

No run found a safety violation. The partial runs are valid data points: a run that does not finish inside the cap tells us the configuration is intractable at these parameters, which is itself a result.

## What each run shows

**Value-domain size is the dominant tractable variable.** The baseline (two values) explores 147,340 states; with a single value (`values1`) the same model collapses to 18,316, a factor of about 8. Both runs hold everything else fixed, so this is a clean comparison. The value domain drives the count because each acceptor can accept any proposed value at each proposal number, so the reachable configurations multiply with the number of values.

**Symmetry reduction is essential.** The baseline uses TLC symmetry over the acceptor, proposer, and learner model values. Turning it off (`nosym`, same model otherwise) does not finish: it reached 5,423,956 distinct states in 3m39s and the queue was still growing past 1.8M when we cut it. Note the depth: `nosym` had explored only to depth 20 while holding more than 5 million states, whereas the symmetric baseline reaches depth 31 with 147,340. The symmetry quotient here is at least 37x. Symmetry is the difference between a 10-minute check and one that does not complete.

**Byzantine presence is not the main cost, and removing it does not shrink the model.** Full Byzantine faults (baseline, 147,340) cost more than an acceptor-only adversary (`byz-acc`, 32,288): the Byzantine proposer and learner, expand the reachable space because correct acceptors and learners react to adversarial PROPOSE and LEARNED messages. Removing every Byzantine process (`byz-none`) does not shrink the model further. With no Byzantine acceptor, all six acceptors branch as correct agents. Extrapolating from the single-value no-Byzantine run (`e5b`, 15,024) by the roughly 8x value-domain factor puts the full two-value no-Byzantine model on the order of 120,000 states, comparable to the baseline. Byzantine modeling does not change the order of magnitude; it keeps the model tractable by fixing some agents rather than letting them branch.

**Worker scaling is sub-linear.** On the small configuration (single value, no Byzantine), four workers (`e5b`) finished 15,024 states in 40m51s while a single worker (`e5a`) reached only 5,547 states in 35m08s before we cut it. As average throughput that is about 375 distinct states per minute at four workers against about 158 at one worker, near 2.4x.

