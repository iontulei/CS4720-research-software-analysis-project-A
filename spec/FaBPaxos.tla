------------------------------ MODULE FaBPaxos ------------------------------
(***************************************************************************)
(* Simplified FaB Paxos - a TLA+ specification of the common case and      *)
(* recovery of the Fast Byzantine Consensus protocol described in          *)
(*                                                                         *)
(*   Martin, J.-P. & Alvisi, L. (2006). Fast Byzantine Consensus.          *)
(*   IEEE Transactions on Dependable and Secure Computing, 3(3), 202-215.  *)
(*                                                                         *)
(* Modeling choices:                                                       *)
(*   - The progress certificate is NOT carried inside the PROPOSE message. *)
(*     The paper's certificate is a-f SIGNED REP pairs, and Lemma 4's      *)
(*     proof turns on the signatures, not on the leader bundling them.     *)
(*     So both the leader's value choice and the acceptor's value-switch   *)
(*     check verify against the signed REP messages already in `msgs`. A   *)
(*     Byzantine leader cannot forge a correct acceptor's REP, because the *)
(*     `acc` field of a Byzantine message is fixed to a Byzantine id.      *)
(*   - Leader election is abstracted as a nondeterministic action.         *)
(*   - State machine replication, parameterized FaB, tentative execution,  *)
(*     and explicit cryptography are out of scope.                         *)
(*                                                                         *)
(***************************************************************************)
EXTENDS Integers, FiniteSets

CONSTANTS
  Acceptors,     \* set of acceptor identifiers
  Proposers,     \* set of proposer identifiers
  Learners,      \* set of learner identifiers
  ByzAcceptors,  \* SUBSET Acceptors, the Byzantine acceptors (fixed at startup)
  ByzProposers,  \* SUBSET Proposers, the Byzantine proposers (incl. possible leader)
  ByzLearners,   \* SUBSET Learners, the Byzantine learners
  Value,         \* set of values that may be proposed
  MaxPN,         \* upper bound on proposal numbers (aka leader changes)
  F,             \* the Byzantine-fault budget, f
  None,          \* used for "no (value, pn) pair"
  NoValue        \* "used for no value yet"

ASSUME ByzAccSubset    == ByzAcceptors \subseteq Acceptors
ASSUME ByzPropSubset   == ByzProposers \subseteq Proposers
ASSUME ByzLearnSubset  == ByzLearners  \subseteq Learners
ASSUME ByzAccBound     == Cardinality(ByzAcceptors) <= F
ASSUME ByzPropBound    == Cardinality(ByzProposers) <= F
ASSUME ByzLearnBound   == Cardinality(ByzLearners)  <= F
ASSUME AcceptorCount   == Cardinality(Acceptors) >= 5 * F + 1
ASSUME ProposerCount   == Cardinality(Proposers) >= 3 * F + 1
ASSUME LearnerCount    == Cardinality(Learners)  >= 3 * F + 1
ASSUME ValueNonEmpty   == Value # {}
ASSUME MaxPNNonNeg     == MaxPN >= 0
ASSUME FNonNeg         == F >= 0
ASSUME NoValueDistinct == NoValue \notin Value
ASSUME NoneDistinct    == \A v \in Value, pn \in 0..MaxPN : None # <<v, pn>>

PN == 0 .. MaxPN
CorrectAcceptors == Acceptors \ ByzAcceptors
CorrectProposers == Proposers \ ByzProposers
CorrectLearners  == Learners  \ ByzLearners

(***************************************************************************)
(*                            MESSAGE SCHEMA                               *)
(* The PROPOSE message carries only (value, pn). The progress certificate  *)
(* is not bundled into it.                                                 *)
(***************************************************************************)
ProgressCertRecord == [acc : Acceptors, value : Value \cup {NoValue}, pn : PN]

Message ==
       [type : {"PROPOSE"},  value   : Value,     pn : PN]
  \cup [type : {"ACCEPTED"}, acc     : Acceptors, value : Value, pn : PN]
  \cup [type : {"LEARNED"},  learner : Learners,  value : Value, pn : PN]
  \cup [type : {"QUERY"},    pn      : PN]
  \cup [type : {"REP"},      acc     : Acceptors, value : Value \cup {NoValue}, pn : PN]

(***************************************************************************)
(*                            STATE VARIABLES                              *)
(***************************************************************************)
VARIABLES
  msgs,           \* set of all messages ever sent (global network buffer)
  accAccepted,    \* [Acceptors -> (Value \X PN) \cup {None}]
  accLargestPN,   \* [Acceptors -> PN \cup {-1}]
  lnLearned,      \* [Learners  -> (Value \X PN) \cup {None}]
  prSuspects,     \* [Proposers -> BOOLEAN]
  leader,         \* the current leader proposer (may be Byzantine)
  currentPN       \* current proposal number

vars == <<msgs, accAccepted, accLargestPN, lnLearned, prSuspects, leader, currentPN>>

(***************************************************************************)
(*                          QUORUM OPERATORS                               *)
(* Integer ceilings via ((x + 1) \div 2). See paper section 2.4.           *)
(***************************************************************************)
FastLearnQuorum  == (Cardinality(Acceptors) + 3 * F + 1 + 1) \div 2  \* ceil((a + 3f + 1) / 2)
ChosenThreshold  == (Cardinality(Acceptors) + F + 1 + 1) \div 2      \* ceil((a + f + 1) / 2)
PullCrossCheck   == F + 1
SuspectThreshold == (Cardinality(Proposers) + F + 1 + 1) \div 2      \* ceil((p + f + 1) / 2)

NumAcceptedMessages(v, pn) ==
  Cardinality({m \in msgs : m.type = "ACCEPTED" /\ m.value = v /\ m.pn = pn})

(* Counts ACCEPTED messages emitted by *correct* acceptors.                *)
NumAcceptedMessagesCorrect(v, pn) ==
  Cardinality({m \in msgs :
                 /\ m.type = "ACCEPTED"
                 /\ m.acc \in CorrectAcceptors
                 /\ m.value = v
                 /\ m.pn = pn})

NumLearnedMessages(v, pn) ==
  Cardinality({m \in msgs : m.type = "LEARNED" /\ m.value = v /\ m.pn = pn})

Chosen(v, pn) == NumAcceptedMessagesCorrect(v, pn) >= ChosenThreshold

(* Progress-certificate vouching, paper section 5.3.2.                     *)
Vouches(pc, v, pn) ==
  /\ pc \subseteq ProgressCertRecord
  /\ Cardinality(pc) = Cardinality(Acceptors) - F
  /\ \A v2 \in Value :
        v2 # v =>
          Cardinality({r \in pc : r.value = v2})
            < (Cardinality(Acceptors) - F + 1 + 1) \div 2

VouchedAtPN(v, pn) ==
  \E repSet \in SUBSET {m \in msgs : m.type = "REP" /\ m.pn = pn} :
      LET pc == {[acc |-> r.acc, value |-> r.value, pn |-> r.pn] : r \in repSet}
      IN  /\ Cardinality(repSet) = Cardinality(Acceptors) - F
          /\ Cardinality({r.acc : r \in repSet}) = Cardinality(Acceptors) - F  \* a-f DISTINCT acceptors
          /\ Vouches(pc, v, pn)

(***************************************************************************)
(*                  BYZANTINE BASELINE (maximal adversary)                 *)
(* Byzantine acceptors and learners may send any well-typed message at any *)
(* time, stamped with their own id. Rather than model that as actions that *)
(* nondeterministically add each message. We inject the full set they      *)
(* could ever send at Init.                                                *)
(***************************************************************************)
ByzAcceptedMsgs ==
  {[type |-> "ACCEPTED", acc |-> a, value |-> v, pn |-> pn] :
     a \in ByzAcceptors, v \in Value, pn \in PN}
ByzRepMsgs ==
  {[type |-> "REP", acc |-> a, value |-> v, pn |-> pn] :
     a \in ByzAcceptors, v \in (Value \cup {NoValue}), pn \in PN}
ByzLearnedMsgs ==
  {[type |-> "LEARNED", learner |-> l, value |-> v, pn |-> pn] :
     l \in ByzLearners, v \in Value, pn \in PN}
ByzBaseline == ByzAcceptedMsgs \cup ByzRepMsgs \cup ByzLearnedMsgs

(***************************************************************************)
(*                                Init                                     *)
(***************************************************************************)
Init ==
  /\ msgs         = ByzBaseline
  /\ accAccepted  = [a \in Acceptors |-> None]
  /\ accLargestPN = [a \in Acceptors |-> -1]
  /\ lnLearned    = [l \in Learners  |-> None]
  /\ prSuspects   = [p \in Proposers |-> FALSE]
  /\ leader       \in Proposers
  /\ currentPN    = 0

(***************************************************************************)
(*                              ACTIONS                                    *)
(***************************************************************************)
Send(m) == msgs' = msgs \cup {m}

(***************************************************************************)
(*                      COMMON CASE + RECOVERY                             *)
(***************************************************************************)

LeaderPropose ==
  /\ leader \in CorrectProposers
  /\ ~ \E m \in msgs : m.type = "PROPOSE" /\ m.pn = currentPN
  /\ \E v \in Value :
       /\ \/ currentPN = 0
          \/ /\ currentPN > 0
             /\ VouchedAtPN(v, currentPN)
       /\ Send([type |-> "PROPOSE", value |-> v, pn |-> currentPN])
  /\ UNCHANGED <<accAccepted, accLargestPN, lnLearned, prSuspects, leader, currentPN>>

(* Correct acceptor accepts a proposed (value, pn). The vouch check is the *)
(* load-bearing defense against a Byzantine leader's poisonous write.      *)
Accept(a) ==
  /\ a \in CorrectAcceptors
  /\ \E m \in msgs :
       /\ m.type = "PROPOSE"
       /\ m.pn >= accLargestPN[a]
       /\ \/ accAccepted[a] = None
          \/ /\ accAccepted[a] # None
             /\ LET v0  == accAccepted[a][1]
                    pn0 == accAccepted[a][2]
                IN \/ /\ pn0 < m.pn
                      /\ \/ v0 = m.value
                         \/ VouchedAtPN(m.value, m.pn)
                   \/ pn0 = m.pn /\ v0 = m.value
       /\ accAccepted' = [accAccepted EXCEPT ![a] = <<m.value, m.pn>>]
       /\ Send([type |-> "ACCEPTED", acc |-> a, value |-> m.value, pn |-> m.pn])
  /\ UNCHANGED <<accLargestPN, lnLearned, prSuspects, leader, currentPN>>

(* Learner learns on a fast quorum of matching ACCEPTED messages           *)
(* Only correct learners record a decision.                                *)
Learn(l) ==
  /\ l \in CorrectLearners
  /\ lnLearned[l] = None
  /\ \E v \in Value, pn \in PN :
       /\ NumAcceptedMessages(v, pn) >= FastLearnQuorum
       /\ lnLearned' = [lnLearned EXCEPT ![l] = <<v, pn>>]
       /\ Send([type |-> "LEARNED", learner |-> l, value |-> v, pn |-> pn])
  /\ UNCHANGED <<accAccepted, accLargestPN, prSuspects, leader, currentPN>>

(* A correct learner adopts a value on f + 1 matching LEARNED reports      *)
(* With f + 1 reports at least one comes from a correct learner, so the    *)
(* value was chosen. The paper's explicit PULL request is omitted.         *)
LearnViaPull(l) ==
  /\ l \in CorrectLearners
  /\ lnLearned[l] = None
  /\ \E v \in Value, pn \in PN :
       /\ NumLearnedMessages(v, pn) >= PullCrossCheck
       /\ lnLearned' = [lnLearned EXCEPT ![l] = <<v, pn>>]
  /\ UNCHANGED <<msgs, accAccepted, accLargestPN, prSuspects, leader, currentPN>>

(***************************************************************************)
(*                          LEADER ELECTION (abstracted)                   *)
(***************************************************************************)

(* A proposer's timeout fires and it suspects the current leader.          *)
SuspectLeader(p) ==
  /\ ~prSuspects[p]
  /\ prSuspects' = [prSuspects EXCEPT ![p] = TRUE]
  /\ UNCHANGED <<msgs, accAccepted, accLargestPN, lnLearned, leader, currentPN>>

(* Abstracted leader election: when a threshold of proposers suspect the   *)
(* leader, a fresh leader is designated with a strictly higher proposal    *)
(* number. The new leader may be Byzantine, which is exactly the case the  *)
(* recovery certificate defends against.                                   *)
LeaderChange ==
  /\ Cardinality({p \in Proposers : prSuspects[p]}) >= SuspectThreshold
  /\ currentPN < MaxPN
  /\ \E newLeader \in Proposers :
       /\ newLeader # leader
       /\ leader' = newLeader
       /\ currentPN' = currentPN + 1
       /\ prSuspects' = [p \in Proposers |-> FALSE]
  /\ UNCHANGED <<msgs, accAccepted, accLargestPN, lnLearned>>

(*A correct new leader broadcasts a QUERY to gather a progress certificate.*)
Query ==
  /\ leader \in CorrectProposers
  /\ currentPN > 0
  /\ ~ \E m \in msgs : m.type = "QUERY" /\ m.pn = currentPN
  /\ Send([type |-> "QUERY", pn |-> currentPN])
  /\ UNCHANGED <<accAccepted, accLargestPN, lnLearned, prSuspects, leader, currentPN>>

(* A correct acceptor answers a QUERY with its currently accepted value as *)
(* a signed REP, and changes its largest seen pn.                          *)
Reply(a) ==
  /\ a \in CorrectAcceptors
  /\ \E m \in msgs :
       /\ m.type = "QUERY"
       /\ m.pn > accLargestPN[a]
       /\ accLargestPN' = [accLargestPN EXCEPT ![a] = m.pn]
       /\ LET v == IF accAccepted[a] = None THEN NoValue ELSE accAccepted[a][1]
          IN Send([type |-> "REP", acc |-> a, value |-> v, pn |-> m.pn])
  /\ UNCHANGED <<accAccepted, lnLearned, prSuspects, leader, currentPN>>

(***************************************************************************)
(*                          BYZANTINE ACTIONS                              *)
(* Byzantine acceptor and learner messages are injected at Init (see       *)
(* ByzBaseline above), so the only dynamic Byzantine action is the         *)
(* leader's poisonous write, which depends on who holds leadership.        *)
(***************************************************************************)

(* A Byzantine leader performs a poisonous write: it proposes any value at *)
(* the current proposal number, with no one-per-pn limit and no vouch      *)
(*constraint. Correct acceptors defend via the VouchedAtPN check in Accept.*)
ByzantinePropose ==
  /\ leader \in ByzProposers
  /\ \E v \in Value :
       Send([type |-> "PROPOSE", value |-> v, pn |-> currentPN])
  /\ UNCHANGED <<accAccepted, accLargestPN, lnLearned, prSuspects, leader, currentPN>>

(***************************************************************************)
(*                                Next                                     *)
(***************************************************************************)
Next ==
  \/ LeaderPropose
  \/ Query
  \/ LeaderChange
  \/ ByzantinePropose
  \/ \E a \in Acceptors : Accept(a) \/ Reply(a)
  \/ \E p \in Proposers : SuspectLeader(p)
  \/ \E l \in Learners  : Learn(l) \/ LearnViaPull(l)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(*                          TYPE INVARIANT                                 *)
(***************************************************************************)
TypeOK ==
  /\ msgs \subseteq Message
  /\ accAccepted  \in [Acceptors -> (Value \X PN) \cup {None}]
  /\ accLargestPN \in [Acceptors -> PN \cup {-1}]
  /\ lnLearned    \in [Learners  -> (Value \X PN) \cup {None}]
  /\ prSuspects   \in [Proposers -> BOOLEAN]
  /\ leader \in Proposers
  /\ currentPN \in PN

(***************************************************************************)
(*                       SAFETY INVARIANTS                                 *)
(***************************************************************************)

(* CS1 (paper section 1, p. 1): only a value that has been proposed may    *)
(* be chosen. Exactly worded as value proposed by any proposer. This       *)
(* could either be a value proposed by a correct or a Byzantine proposer.  *)
CS1Inv ==
  \A v \in Value, pn \in PN :
    Chosen(v, pn) =>
      \E m \in msgs : m.type = "PROPOSE" /\ m.value = v /\ m.pn = pn

(* CS2 (paper section 1, p. 1): only a single value may be chosen.         *)
CS2Inv ==
  \A v1, v2 \in Value, pn1, pn2 \in PN :
    Chosen(v1, pn1) /\ Chosen(v2, pn2) => v1 = v2

(* CS3 (paper section 1, p. 1): only a chosen value may be learned by a    *)
(* CORRECT learner.                                                        *)
CS3Inv ==
  \A l \in CorrectLearners :
    lnLearned[l] # None =>
      LET v  == lnLearned[l][1]
          pn == lnLearned[l][2]
      IN Chosen(v, pn)

=============================================================================
