#import "./diagrams.typ": diagrams

#set page(
  numbering: "1 / 1",
)

#set heading(
  numbering: "1.",
)

// #let refs = yaml("bib.yml")
// #refs.at("ot-jupiter-paper").title

#outline()


= Introduction

Web is a technology that changed the world. Because of it's decentralized nature


= Task requirements <h1:task-requirements>

The implementation should meet the following requirements:

- Guaranteed convergence. If all replicas receive the same set of updates, they
  must eventually reach the same state.
- High interactivity. Local changes should be applied with very low latency,
  ideally below $tilde.basic 100$ms.
- Real-time collaboration. Remote updates should propagate quickly enough for
  collaborative editing to feel natural.
- Fully distributed operation. The system should not require additional
  infrastructure, such as a central server, for synchronization or concurrency
  control.
- Dynamic membership. Participants may join or leave the system at any time.
- Tolerance to network faults and offline editing. The system should continue to
  operate under message delays, reordering, temporary disconnection, and offline
  work.
- Preservation of user edits. Concurrent edits should not be silently lost.
- Scalability. The system should remain practical for a large number of
  participants ($gt 100$).


= Shared Editing Algorithms

Shared editing algorithms can be classified in multiple ways. From the
perspective of concurrency control, they are commonly divided into two
categories:

- *Pessimistic* updates require acquiring a lock with other sites (or a central
  server) before applying changes.
- *Optimistic:* updates are immediately visible to the user in the local copy,
  while conflicts caused by concurrent edits are resolved later. This makes
  optimistic approaches better suited to high-latency communication
  environments. @ot-jupiter-paper

Pessimistic algorithms are mature and widely used in practice. Common techniques
include locking, transactions, single active participation, dependency detection
@concurrency-control-classification.

Optimistic approaches are more common in modern collaborative editing research.
Two of the most prominent families are Operational Transformation (OT)
(@concurrency-control-classification, @ot-introduction-blog) and Conflict-free
Replicated Data Types (CRDTs) @crdt-yjs-paper. A related optimistic
synchronization technique is three-way merge, widely used in version control
systems, such as git @git-three-way-merge.


== Operational Transformation (OT)

In OT changes are represented as operations such as _insert_ and _delete_. This
representation is more flexible than reasoning about whole-document replacements
@ot-introduction-blog.

A simple example illustrates this idea. Suppose both client and server start
from the same state ("Hola"). Client performs a changeset $a$:
- remove "o" at position 2: "Hola" $arrow$ "Hla"
- remove "a" at position 3: "Hla" $arrow$ "Hl"
While the server receives a changeset $b$:
- insert "e" at position 2: "Hola" $arrow$ "Heola"
- insert "l" at position 4: "Heola" $arrow$ "Heolla"
- insert "o" at position 5: "Heolla" $arrow$ "Heolola"

If these changes are applied without transformation, the client ends up with
"Hello", and the server will end up with "Hoola"

Formally, OT defines a transformation function @ot-small-implementation-blog:
$
  "xform"(a, b) = (a', b'), "such that" b' circle.stroked.tiny a equiv a' circle.stroked.tiny b
$

In other words, given two concurrent operations, the transformation function
produces adjusted operations $a'$ and $b'$ such that applying $a$ followed by
$b'$ yields the same result as applying $b$ followed by $a'$. (see
@fig:ot-basic)

#figure(
  stack(
    diagrams.ot-basic,
    diagrams.ot-transformed,
    dir: ltr,
    spacing: 2em,
  ),
  caption: [Diamond property],
) <fig:ot-basic>

This diamond property is the core idea behind OT, but it gets much more
complicated when the state diverges more than on one step @ot-introduction-blog
(see @fig:ot-extended), and formal proofs of correctness are very complicated
and error-prone, even for the simplest case with two operations (delete and
insert) @ot-wikipedia

#figure(
  diagrams.ot-extended,
  caption: [OT transformation complexity],
) <fig:ot-extended>

OT is commonly used in a client-server architecture. Both the client and the
server may perform operational transformation, but the server acts as the
central coordination point that establishes a consistent integration order for
all replicas.

Joseph Gentle (former Google Wave OT engineer) also noted:

#quote(
  block: true,
  attribution: [Joseph Gentle @ot-hacker-news-jospeh-gentle],
)[
  ... about OT - it gets crazy complicated if you implement it in a distributed
  fashion. But implementing it in a centralized fashion is actually not so bad.
  Its the perfect choice for google docs.
]

Algorithmic complexity is not the only reason why OT is less suitable for
peer-to-peer communication. Some decentralized OT protocols use metadata such as
vector clocks to track causality between operations. Since this metadata may
grow with the number of participants, such approaches become less attractive for
large or dynamic peer-to-peer groups @ot-data-consistency-for-p2p.

OT is historically associated with products like Google Docs @ot-wikipedia; the
product currently limits the number of concurrent users to 100
@google-support-sharing.


== Conflict-free Replicated Data Types (CRDTs)

CRDTs are replicated data structures designed so that multiple replicas can be
updated independently and still converge to the same state after
synchronization. Two common families are state-based CRDTs (CvRDTs) and
operation-based CRDTs (CmRDTs). This section focuses on state-based CRDTs.

The key requirement that the set of states form a join semilattice (see
@fig:subset-lattice), meaning that there is a partial order $<=$ defined, and
any two states $x$ and $y$ have a least upper bound ($x union.sq y$) state.

#figure(
  diagrams.subset-lattice,
  caption: [Subset lattice under set inclusion],
) <fig:subset-lattice>

Any local updates must be monotonic, meaning that the state of the system can
only move upward in the partial order, and to guarantee convergence the merge
operation (_join_ function) must be
- commutative: $x union.sq y = y union.sq x$
- associative: $x union.sq (y union.sq z) = (x union.sq y) union.sq z$
- idempotent: $x union.sq x = x$ @crdt-basic-paper

A common example is the grow-only counter (G-Counter) @crdt-g-counter-example.
Consider a distributed service that stores the number of likes on a post. To
scale the system, user requests may be handled by different servers. Suppose two
replicas, $a$ and $b$, start from the same visible value $0$.

If the state were represented by a single integer, concurrent increments could
be lost:
- a "like" request reaches replica $a$: $0 arrow 1$
- a "like" request reaches replica $b$: $0 arrow 1$
- after synchronization, merging the two states still yields $1$

Thus, a single integer is not sufficient to represent concurrent increments.

To solve this problem, a G-Counter stores a vector of per-replica counters,
where each replica increments only its own component @crdt-basic-paper-2.
- replica $a$: $[0, 0] arrow [1, 0]$
- replica $b$: $[0, 0] arrow [0, 1]$
- after synchronization, the states are merged componentwise using $max$:
  $[1, 0] union.sq [0, 1] = [max(1, 0), max(0, 1)] = [1, 1]$

The visible counter value is obtained by summing all components, which gives the
correct total value $2$.

Deletion is harder because it usually reduces the state (non-monotonic update),
which breaks the semilattice requirement. To solve this problem, CRDTs often use
tombstones (markers for deleted items). The simplest example is 2P-Set
represented as two grow-only sets: $AA$ for added elements and $RR$ for removed
elements, with the visible set defined as $AA backslash RR$. Once an element is
placed in $RR$, it cannot be added again. In this sense, tombstones preserve
enough history for merges. @crdt-tombstones

These ideas are not merely theoretical. CRDTs have been studied formally,
including machine-checked verification @crdt-verification, and are also used in
production systems such as Redis @crdt-redis, Zed @crdt-zed, collaborative typst
editor @crdt-yjs-typst and others. They have also influenced newer collaborative
architectures such as Figma's, which draws on similar ideas but is not a pure
CRDT design @figma-architecture.

== Three-way merge

Three-way merge is another technique based on optimistic concurrency control,
and is most commonly associated with version control systems. It allows
modification of local copies independently and reconciles the results, often
much later in time. The merge process is computed from three inputs, namely the
two modified versions and their common ancestor. If both sides changed the same
fragment in incompatible ways, the algorithm reports a conflict, which usually
has to be resolved manually (see @fig:three-way-merge).

#figure(
  diagrams.three-way-merge,
  caption: [Three-way merge],
) <fig:three-way-merge>

It is generally better suited to asynchronous branch-style workflows than to
real-time collaborative editing.

== Comparison

#table(
  columns: (1fr, 1fr, 1fr, 1fr),
  align: horizon,
  table.header([Characteristic], [Three way merge], [OT], [CRDT]),

  [Real-time collaboration], [Poor], [Good], [Good],

  [Immediate local updates], [Good], [Good], [Good],

  [Fully distributed operation],
  [Good],
  [Poor. Possible in theory, but hard in practice],
  [Good],

  [Offline editing (delayed synchronization)],
  [Good],
  [Medium. Possible but reconciliation becomes complex],
  [Good],

  [Dynamic membership], [Good], [Medium], [Good],

  [Manual conflict resolution], [Yes], [No], [No],

  [Mathematical convergence guarantees], [No], [Yes], [Yes],

  [Implementation complexity], [Low], [High], [High],

  [Synchronization metadata overhead], [Low], [Medium to High], [Low to Medium],

  [Document state metadata overhead], [Low], [Low to Medium], [High],
)

== Conclusion

Given the requirements of this work (@h1:task-requirements), CRDT is the most
suitable choice. Three-way merge is useful as a conceptual optimistic baseline,
but it is better suited to asynchronous version-control workflows. OT is a
strong option for centralized real-time editors, but it is a weaker fit when the
goal is a decentralized system without a permanent coordination server.


#bibliography("./bib.yml")
