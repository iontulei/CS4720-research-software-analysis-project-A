--------------------------- MODULE MCFaBPaxosTrace ---------------------------
(****************************************************************************)
(* Trace generation for Simplified FaB Paxos. This module exists only to    *)
(* produce example executions of the protocol.                              *)
(*                                                                          *)
(* It reuses the protocol from `FaBPaxos.tla` without changing it, and adds *)
(* read-only observer invariants. Each observer says "the goal has not      *)
(* happened yet". TLC's breadth-first search then returns the shortest run  *)
(* that reaches the goal, as a counterexample to the observer. Because the  *)
(* observers appear in no action, guard, or threshold, the set of behaviors *)
(* is exactly that of the real protocol; the printed counterexample is a    *)
(* faithful execution of the UNMODIFIED protocol.                           *)
(*                                                                          *)
(* This is the opposite of the mutation and load-bearing tests, which       *)
(* changed protocol logic. Here nothing in FaBPaxos.tla is touched.         *)
(*                                                                          *)
(* Generate (run from `spec/`, capture stdout):                             *)
(*   java -jar ~/tools/tla2tools.jar -fp 1 \                                *)
(*        -config traces/common-case.cfg MCFaBPaxosTrace.tla                *)
(*                                                                          *)
(* See traces/README.md for all three scenarios.                            *)
(****************************************************************************)
EXTENDS FaBPaxos

NeverLearned == \A l \in Learners : lnLearned[l] = None

NeverLearnedAtPN1 ==
  \A l \in Learners : lnLearned[l] = None \/ lnLearned[l][2] # 1

==============================================================================
