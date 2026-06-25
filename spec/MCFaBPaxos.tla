------------------------------ MODULE MCFaBPaxos ------------------------------
(***************************************************************************)
(* Model-checking wrapper for `FaBPaxos.tla`. The concrete CONSTANTS are   *)
(* declared in `MCFaBPaxos.cfg` as model values (required by TLC's         *)
(* SYMMETRY feature). This module defines the state constraint and the     *)
(* symmetry-permutation set.                                               *)
(*                                                                         *)
(* Concrete configuration (in .cfg), full per-class Byzantine threat:      *)
(*   - 6 acceptors, 1 Byzantine                                            *)
(*   - 4 proposers, 1 Byzantine (the leader may become Byzantine)          *)
(*   - 4 learners, 1 Byzantine                                             *)
(*   - 2 candidate values                                                  *)
(*   - proposal numbers 0..MaxPN                                           *)
(*   - F = 1                                                               *)
(*                                                                         *)
(* Run from `spec/`:                                                       *)
(*   java -jar ~/tools/tla2tools.jar -workers 4 \                          *)
(*        -config MCFaBPaxos.cfg MCFaBPaxos.tla                            *)
(***************************************************************************)
EXTENDS FaBPaxos, TLC

(* Bound message-buffer growth so TLC terminates; safety net only. The     *)
(* Byzantine baseline (injected at Init) is ~14 messages at MaxPN=1, and   *)
(* the correct protocol adds ~24 more over a full two-term run, so the cap *)
(* must clear ~40.                                                         *)
StateConstraint == Cardinality(msgs) <= 60

(* Symmetry permutes only the CORRECT agents of each class.                *)
(* Values are not permuted so traces show which specific value is chosen.  *)
Symmetry ==
  Permutations(Proposers \ ByzProposers)
    \cup Permutations(Learners \ ByzLearners)
    \cup Permutations(Acceptors \ ByzAcceptors)

===============================================================================
