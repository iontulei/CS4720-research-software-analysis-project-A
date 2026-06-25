-------------------------- MODULE MCFaBPaxosLiveness --------------------------
(****************************************************************************)
(* Liveness model for Simplified FaB Paxos. It reuses the protocol from     *)
(* `FaBPaxos.tla` and adds fairness plus the two liveness properties of     *)
(* the paper:                                                               *)
(*                                                                          *)
(*   CL1: some proposed value is eventually chosen.                         *)
(*   CL2: once a value is chosen, every correct learner eventually learns   *)
(*        it (paper section 1, proved in section 5.4 via Lemma 5).          *)
(*                                                                          *)
(* Liveness is impossible under full asynchrony, so the paper guarantees it *)
(* only during synchrony with an eventually stable correct leader (Lemma 5: *)
(* "if alpha is correct then some value will be stable").                   *)
(*  We encode that by setting ByzProposers = {} (the leader is always       *)
(*  correct). because LeaderChange requires currentPN < MaxPN, after at     *)
(* most MaxPN changes the leader is stable.                                 *)
(*                                                                          *)
(* Byzantine acceptors and learners stay present (ByzAcceptors,             *)
(* ByzLearners are non-empty in the cfg), so liveness is checked against    *)
(* acceptor and learner faults, matching Lemma 5.                           *)
(*                                                                          *)
(* Run from `spec/`:                                                        *)
(*   java -jar ~/tools/tla2tools.jar -workers 4 -deadlock -lncheck final \  *)
(*        -config MCFaBPaxosLiveness.cfg MCFaBPaxosLiveness.tla             *)
(*                                                                          *)
(* The cfg has no SYMMETRY and no CONSTRAINT: both are unsound for liveness *)
(* (they can hide a counterexample).                                        *)
(****************************************************************************)
EXTENDS FaBPaxos

Fairness ==
  /\ WF_vars(LeaderPropose)
  /\ WF_vars(Query)
  /\ \A a \in CorrectAcceptors : WF_vars(Accept(a))
  /\ \A a \in CorrectAcceptors : WF_vars(Reply(a))
  /\ \A l \in CorrectLearners  : WF_vars(Learn(l) \/ LearnViaPull(l))

LiveSpec == Spec /\ Fairness

(* Requiring a specific pn would be wrong when the same value is chosen at  *)
(* more than one pn.                                                        *)
LearnedValue(l, v) == lnLearned[l] # None /\ lnLearned[l][1] = v

CL1 == <>(\E v \in Value, pn \in PN : Chosen(v, pn))

CL2 == \A v \in Value :
         (\E pn \in PN : Chosen(v, pn))
           ~> (\A l \in CorrectLearners : LearnedValue(l, v))

===============================================================================
