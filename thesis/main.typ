#import "./diagrams.typ": diagrams
#import "./protocol_diagrams.typ": protocol-diagrams

#set page(
  numbering: "1 / 1",
)

#set heading(
  numbering: "1.",
)

#outline()

= Task requirements <h1:task-requirements>

The implementation should meet the following requirements:

- Guaranteed convergence. If all replicas receive the same set of updates, they
  must eventually reach the same state.
- Preservation of user intent. Concurrent edits should not be silently lost. The
  merged result should reflect what users would "reasonably" expect from
  applying their edits
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
- Scalability. The system should remain practical for a large number of
  participants ($gt 100$).
- The implementation should work in a web browser environment.


= Shared Editing Algorithms

Shared editing algorithms can be classified in multiple ways. From the
perspective of concurrency control, they are commonly divided into two
categories:

- *Pessimistic* updates require acquiring a lock with other sites (or a central
  server) before applying changes.
- *Optimistic:* updates are immediately visible to the user in the local copy,
  while conflicts caused by concurrent edits are resolved later. This makes
  optimistic approaches better suited to high-latency communication
  environments. @ot-jupiter-paper[p. 112]

Pessimistic algorithms are mature and widely used in practice. Common techniques
include locking, transactions, single active participation, dependency detection
@concurrency-control-classification[p. 401].

Optimistic approaches are more common in modern collaborative editing research.
Two of the most prominent families are Operational Transformation (OT) and
Conflict-free Replicated Data Types (CRDTs). A related optimistic
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
peer-to-peer communication. In decentralized settings, OT often requires extra
causality-tracking and coordination metadata to determine when operations are
concurrent and how they should be transformed. As the number of participants
grows, maintaining this metadata and preserving consistent transformation
behavior becomes more difficult. This makes OT less attractive for large or
highly dynamic peer-to-peer groups @ot-data-consistency-for-p2p[p. 259].

OT is historically associated with products like Google Docs @ot-google-docs;
the product currently limits the number of concurrent users to 100
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
- idempotent: $x union.sq x = x$ @crdt-basic-paper-2[p. 6]

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
where each replica increments only its own component @crdt-basic-paper-2[p.
  11]. <g-counter-example>
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

Given the requirements of this work (@h1:task-requirements), CRDT is the most
suitable choice. Three-way merge is useful as a conceptual optimistic baseline,
but it is better suited to asynchronous version-control workflows. OT is a
strong option for centralized real-time editors, but it is a weaker fit when the
goal is a decentralized system without a permanent coordination server.

= Text CRDTs Implementations

Text documents are more complex than simple CRDT counters or sets because text
is an ordered sequence of elements. A text CRDT must preserve the order of
inserted characters or text fragments, resolve concurrent insertions
deterministically, and support deletion without breaking convergence. Therefore,
practical collaborative editors use specialized sequence CRDT designs.

This section compares several practical CRDT implementations that can be used
for collaborative text editing.

*Yjs* @crdt-yjs-github is a YATA-based CRDT implementation that supports
collaborative text, rich text, and other shared data types that can be composed
into more complex document structures @crdt-yjs-paper. Yjs is optimized for
practical editing workloads. In particular, it takes advantage of the fact that
users often insert text in contiguous chunks and usually edit from left to
right. It also uses a compact binary encoding for synchronization messages,
which helps reduce bandwidth usage.

Yjs is implemented in JavaScript and is designed to work in web browsers.
Although modern JavaScript engines optimize objects with stable shapes
@v8-fast-properties, each object still carries runtime metadata and contributes
to memory-management overhead. This makes compact internal representation
important for large collaborative documents. There is also a Rust implementation
of the Yjs/Yrs CRDT model that can be compiled to WebAssembly
@crdt-y-crdt-github.

*Automerge* @crdt-automerge-github is a JSON-like document CRDT with
collaborative text support. Its text model follows ideas from Peritext
@crdt-automerge-text, which makes it suitable not only for plain text, but also
for rich text editing. Unlike algorithm-specific CRDT papers, Automerge does not
appear to provide a simple asymptotic time-complexity analysis for its whole
public API. Its performance is mostly evaluated empirically and depends on the
workload @crdt-automerge-performance-blog, and implementation version.

*json-joy* @crdt-json-joy-rga is a collection of real-time editing algorithms
that includes an RGA-family implementation for text. Its RGA implementation is
not a naive character-by-character linked list, but a block-wise RGA design
intended for practical sequence editing. This makes it useful as an example of
an optimized RGA-based sequence CRDT. However, rich-text intent preservation is
not the main focus of this implementation; Peritext specifically addresses the
problem that naive extensions of plaintext or tree CRDTs may fail to preserve
user intent in rich text editing @crdt-peritext-rich-text.

#figure(
  table(
    columns: (1.15fr, 1.55fr, 1.55fr, 1.55fr),
    align: horizon,
    table.header([Characteristic], [Yjs], [Automerge], [json-joy RGA]),

    [CRDT model],
    [YATA-based CRDT with implementation optimizations],
    [JSON-like CRDT with Peritext-based text model],
    [Block-wise RGA / RGA-split sequence CRDT],

    [Plain text], [Yes], [Yes], [Yes],

    [Rich text],
    [Yes],
    [Yes],
    [Partially; Intent preservation is not guaranteed],

    [Synchronization topology],
    [Network-agnostic; can use client-server or P2P providers such as WebRTC],
    [Uses Automerge sync protocol over an application-chosen transport],
    [Application/library-specific],

    [Performance focus],
    [Optimized for contiguous text edits],
    [General local-first documents; performance depends on history and
      workload],
    [No known additional optimizations],

    [Local insertion],
    [$O(log(H))$ @crdt-yjs-paper[p. 45]],
    [Mostly evaluated empirically],
    [$O(N)$ @crdt-evalution[p. 106]],

    [Local deletion],
    [$O(log(H))$ @crdt-yjs-paper[p. 45]],
    [Mostly evaluated empirically],
    [$O(N)$ @crdt-evalution[p. 106]],

    [Remote insertion],
    [$H^2$ @crdt-yjs-paper[p. 45]],
    [Mostly evaluated empirically],
    [$O(1 + c/n)$ @crdt-evalution[p. 106]],

    [Remote deletion],
    [$O(log(H))$ @crdt-yjs-paper[p. 45]],
    [Mostly evaluated empirically],
    [$O(1)$ @crdt-evalution[p. 106]],

    [Advantages],
    [Efficient text synchronization, compact updates, mature ecosystem, browser
      support, Rust/WASM implementation available],
    [General-purpose local-first document model, rich-text support through
      Peritext ideas, good for structured documents],
    [Less feature rich, so could be easier to understand the implementation],

    [Limitations],
    [Complex internal model; YATA/Yjs implementation details are harder to
      explain than simple academic CRDTs],
    [No simple public asymptotic complexity for the whole API; Less
      text-editing-specific optimizations than Yjs],
    [Less focused on rich-text intent preservation; smaller ecosystem than Yjs
      or Automerge],

    [Suitability], [High], [Medium-high], [Medium],
  ),
  caption: [Comparison of practical CRDT implementations for collaborative text
    editing],
)

- $c$ is the average number of operations concurrent to a given one,
- $n$ is the size of the document (non-deleted characters),
- $N$ is the total number of inserted characters, including deleted characters
  stored as tombstones,
- $H$ is the number of operations that affected the document.

= Implementation

This chapter describes the implementation of text CRDT. It is inspired by Yjs
and the YATA family of sequence CRDTs @crdt-yjs-paper, but it is not a direct
port of Yjs and does not try to be compatible with the Yjs update format.
Instead, it takes the ideas for this project and applies them to a smaller
document model.

This narrower scope is intentional. Yjs is a mature general-purpose shared data
structure library with support for many document types and many production edge
cases. While the goal of this implementation is to build a compact,
understandable CRDT core that is sufficient for a browser-based collaborative
editor. The implementation therefore focuses on the mechanics needed for text
collaboration rather than on reproducing the full Yjs ecosystem.

At the public API level, a document exposes a text object that can:

- insert valid UTF-8 text at a visible character index;
- delete a visible range;
- apply or clear formatting attributes over a range;
- render the current visible text;
- render attributed text as delta-style operations @delta-text-format;
- encode a state vector describing what the replica already knows;
- encode an update relative to another replica's state vector;
- apply updates received from other replicas.

The implementation does not require a central server to decide the final order
of operations. A server may still be used as a transport relay, but the CRDT
state itself is designed so that replicas can edit locally and exchange updates
later. Updates are safe to receive more than once, and updates that arrive
before their dependencies are kept temporarily and retried after later updates.

Internally, the visible document is not stored as a single mutable string. It is
stored as a doubly-linked sequence of CRDT items. Some items contain text, some
contain formatting markers, and deleted content remains as tombstones so that
later remote operations can still refer to stable identifiers.

== Document Model

The most important idea in the implementation is that the CRDT state and the
visible text are not the same thing. The CRDT state stores the editing history
needed for synchronization, while the visible text is derived from that state.

The core unit of this state is an `Item`. An item may represent a fragment of
text, a formatting marker, or deleted content. Text items contribute characters
to the visible document. Formatting markers do not contribute characters and
only change the active attributes for the following text. Deleted items also do
not appear in the visible text, but they remain in the structure so that other
replicas can still refer to their identifiers.

For example, after deleting the middle of a word, the internal sequence may
still contain the deleted fragment:
`[text "h"] -> [deleted text "ell"] -> [text "o"]`. When rendering the document,
the algorithm walks this sequence and emits only visible items - `"ho"`.

Unlike a normal string editor, this representation introduces additional storage
overhead, but it also enables merging and versioning at the data-structure level
@crdt-automerge-local-first.

The same sequence also stores rich-text formatting. A formatting operation is
represented by inserting marker items into the sequence. During rendering, the
implementation keeps track of the currently active formatting attributes and
attaches them to following text items. This keeps plain text and formatting in
one ordered CRDT structure.

Thus, the internal sequence acts as the source of truth, while plain text and
attributed text are derived views.

== Item Identity

Each item needs to have a global unique identifier. A simple way to create
unique identities without a central coordinator is to use UUIDs. UUIDv7 is
especially attractive because it contains a time-ordered field derived from the
Unix epoch timestamp, which makes identifiers approximately sortable by creation
time @uuid7. However, assigning a full UUID to every item would add 16 bytes of
identifier metadata per item. Furthermore the timestamp is based on physical
time, which is not a reliable source of causal ordering in distributed systems
because of clock skew. Logical clocks are a common solution for ordering events
in distributed systems @logical-clocks. Lamport clocks assign a logical
timestamp to each event and can be extended with a replica identifier to obtain
a deterministic total order ($prec$) of operations
@lamport-time-clocks-ordering[pp. 560-562]. This order is defined as follows:

$
  (a prec b) arrow.l.r.double.long (C(a) < C(b) or (C(a) = C(b) and r(a) < r(b)))
$

where $C(a)$ is the Lamport timestamp of operation $a$, and $r(a)$ is the unique
identifier of the replica that generated operation $a$. This total order is
consistent with the happened-before relation ($arrow.r$). If operation $a$
happened before operation $b$, then Lamport clocks guarantee that $C(a) < C(b)$,
and therefore $a$ is ordered before $b$:
$(a arrow.r b) => C(a) < C(b) => (a prec b)$

#figure(
  diagrams.lamport-clocks,
  caption: [Lamport clock updates across three replicas],
) <fig:lamport-clocks>

In the standard Lamport-clock algorithm @fig:lamport-clocks, each replica
increments its local clock before creating an event. When a message is received,
the receiver sets its clock to the maximum of its current local clock and the
message timestamp, then increments it. For example, replica $Z$ receives $m_3$
with timestamp $4$ while its local clock is $2$, so the next timestamp is
$max(2, 4) + 1 = 5$.

The same diagram also shows why Lamport timestamps cannot be used as a complete
causality test. The events $x$ and $y$ have ordered timestamps, $C(x) = 1$ and
$C(y) = 2$, but there is no chain of local steps or messages from $x$ to $y$.
Therefore, $C(x) < C(y)$ does not prove that $x$ caused $y$.

This implementation uses a related idea, but not a full global Lamport clock.
Each item is identified by a pair `Id`:

```zig
pub const ClientId = u64;
pub const Clock = u64;
pub const Id = struct { client: ClientId, clock: Clock, };
```

`ClientId` identifies the replica that created the item, and `Clock` is a
monotonically increasing counter in the `ClientId` history. This is similar to
the #link(<g-counter-example>)[G-Counter example], where each replica advances
only its own component, and synchronization combines knowledge about all
clients.

A text item may cover more than one clock value. For example, if client `1`
inserts `"hello"` into an empty document, the implementation can store it as one
item with id `{1, 0}` and length `5`. This item owns the clock range
`{1, [0..4]}`. The next item created by the same client starts at clock `5`.

The implementation assumes that active replicas use unique client ids and does
not provide client-id generation. In a real application, client ids may come
from account identity, or another application-level mechanism. If two active
replicas use the same `ClientId`, their clock ranges can overlap, and the CRDT
can no longer distinguish their histories correctly.

== Internal Representation

The main data structure that stores the document is `TextImpl`. It contains the
CRDT sequence, the visible text length, the byte storage, and the per-client
clock index required for synchronization.

The document order is represented as a doubly linked list of items. Each item
stores local `left` and `right` handles, while `TextImpl` stores the `start` and
`end` handles of the sequence. This linked order is used when rendering the
document.

Items are not stored in linked-list order in memory. Instead, they are stored in
an array, and an `ItemHandle` is an index into this array. This keeps links
compact: a handle is a `u32`, not a pointer and not a replica-wide identifier.

Therefore, the implementation uses two different ways to refer to an item:

- `ItemHandle` is local to one replica and is used internally for links between
  items;
- `Id` is stable across replicas and is used in synchronization messages.

This distinction is necessary because two replicas may store the same logical
item at different array positions. As a result, updates that describe where an
item was inserted cannot use local handles; they must refer to the stable ids of
neighboring items.

Item content is also stored compactly. Text and attribute strings are kept in a
byte buffer owned by `TextImpl`. An item does not own a separate string;
instead, it stores a range into this buffer. A text slice stores both the byte
range and the logical length in Unicode scalar values. This allows the
implementation to store UTF-8 text while exposing indexes in visible character
units.

For synchronization, the implementation uses `StructStore`. It groups item
handles by the client that created them and keeps each client's items ordered by
clock. For each client, clock ranges must be contiguous. Because of this
ordering, the store can find the item that contains a given `{client, clock}` id
using binary search. This store is used to answer several
synchronization-related questions:

- what clock the next local item should use;
- whether an item id is already known;
- which local handle contains a given `{client, clock}` id;
- what state vector should be sent to another replica;
- which items are missing from another replica's state vector.

Overall, the internal representation combines three views of the same state: the
linked list defines document order, the item array provides compact local
storage, and the struct store indexes items by client and clock for
synchronization.

== Local Editing

Local editing operations are applied immediately on the local replica. The CRDT
metadata is created together with the local change, so the operation can later
be encoded and sent to other replicas.

=== Finding Positions

The public editing API uses visible text indexes. These indexes count Unicode
scalar values in the rendered document, not bytes and not internal items.
Therefore, deleted items and formatting markers must be ignored when translating
a public index into an internal position.

For example, if the internal sequence is
`[text "h"] -> [deleted text "ell"] -> [text "o"]`, then visible index `1`
refers to the position between `"h"` and `"o"`, even though a deleted item
exists between them internally.

A position is represented as a gap between two item handles: the item on the
left and the item on the right. If the requested index falls in the middle of a
text item, the item is split first. For example, inserting at index `2` inside
`[text "hello"]` splits the item into `[text "he"]` and `[text "llo"]`, creating
a clean insertion gap between them.

The new item can then be linked into this gap. Splitting does not copy the
string bytes; it only adjusts the slice metadata of the existing item and
creates a second item pointing into the same byte buffer. The split is performed
on UTF-8 scalar boundaries, so public character indexes remain consistent with
the internal byte representation.

=== Insertion

A plain text insertion follows a small sequence of steps:

- validate that the index is inside the visible document;
- validate the inserted bytes as UTF-8 and compute their Unicode scalar length;
- find the linked-list gap corresponding to the visible index;
- append the inserted bytes to the byte buffer;
- create a new text item with the next `{client, clock}` id;
- store the stable ids of the neighboring items as the item's origins;
- add the item to the struct store;
- link the item into the document order.

The important point is that insertion does not rewrite the whole document. It
creates a new item and places it into the sequence.

Consider these operations on an empty document:

- `insert(0, "Hello")`
- `insert(5, " world")`
- `insert(5, ",")`

#figure(
  table(
    columns: (0.75fr, 1fr, 1.35fr, 1.15fr),
    align: horizon,
    table.header([handle], [id], [content slice], [links]),
    [`h0`], [`{1,0}`], [`bytes[0..5] = "Hello"`], [`left=null, right=h2`],
    [`h1`], [`{1,5}`], [`bytes[5..11] = " world"`], [`left=h2, right=null`],
    [`h2`], [`{1,11}`], [`bytes[11..12] = ","`], [`left=h0, right=h1`],
  ),
  caption: [Item metadata after inserting a comma],
) <fig:local-insert-table>

In @fig:local-insert-table, the comma item is appended as handle `h2`, so it
appears after `h0` and `h1` in the item array. However, the visible document is
not read in array order. It is read by following the linked-list order, which is
`h0 -> h2 -> h1` and renders as `"Hello, world"`.

#figure(
  diagrams.local-insert-state,
  caption: [Document order and shared byte buffer after inserting a comma],
) <fig:local-insert>

@fig:local-insert shows the same state from a different angle. The linked list
defines the document order, while each item points to a slice in the shared byte
buffer. The byte buffer keeps data in append order, so its physical layout does
not have to match the visible document order.

When an item is created, it records origin ids. The left origin is the last id
covered by the left neighbor, and the right origin is the first id of the right
neighbor. These origins describe the gap where the item was originally inserted.
They are not the same as the current `left` and `right` links, since they may
change later when other items are inserted nearby, while origins remain stable.
This allows another replica to insert the item into the same logical gap.

=== Deletion

Deletion also starts from visible indexes. The implementation translates the
requested visible range into internal item boundaries, splits boundary text
items when necessary, and then marks the affected visible text items as deleted.

For example, deleting `"ell"` from `"hello"` can produce the internal sequence
`[text "h"] -> [deleted text "ell"] -> [text "o"]`.

The visible length decreases, but the deleted item remains addressable by its
stable id range. This is necessary because a remote update may still refer to an
item that has already been deleted locally.

== Remote Integration

When a replica receives an update from another replica, it does not apply the
operation by visible index. Visible indexes are local and temporary: while
replicas are missing each other's updates, the same index may refer to different
internal positions. Therefore, remote integration is based on stable item ids
and origin ids.

A remote item contains:

- its own `{client, clock}` id and length;
- the stable id of the item that was on its left when it was created;
- the stable id of the item that was on its right when it was created;
- its content, either text or a formatting marker.

The left and right ids are called origins. They describe the logical gap where
the item was inserted. Local insertion records these origins because local
handles are meaningful only inside one replica, while remote replicas need
stable ids to reconstruct the same insertion context.

For example, if a comma is inserted between `"Hello"` and `" world"`, the remote
update does not say “insert after handle `h0`”, because `h0` exists only on the
sender. Instead, the update says that the new item was inserted after the last
id of `"Hello"` and before the first id of `" world"`. The receiver uses its own
struct store to find the local handles that contain these ids, splits items at
the required clock boundaries when necessary, and links the remote item into the
resulting gap.

Before integrating a remote item, the implementation checks whether it is ready
to be applied. If the item range is already known, the item is ignored. If the
item starts after the next expected clock for that client, or if one of its
origins is still missing, the item cannot be integrated yet. In that case, the
update is kept as pending and retried after later successful integrations. This
allows messages to be delivered out of order without requiring the transport
layer to enforce a single global order.

Remote operations are idempotent. Reintegrating an already known item has no
effect, and applying the same deletion again only keeps the item deleted. This
makes duplicate message delivery safe.

=== Concurrent Inserts

The most important conflict case occurs when two replicas insert into the same
logical gap concurrently. For example, two replicas may both insert at the
beginning of an empty document:


```text
replica A inserts "X"
replica B inserts "Y"
```

Both insertions have no left origin and no right origin, so they target the same
gap. If each replica inserted remote items only according to message arrival
order, the final document order could differ between replicas, which would break
convergence.

To avoid this, the implementation uses a deterministic ordering rule defined at
YATA paper @crdt-yjs-paper. Direct siblings inserted after the same left origin
are ordered by `ClientId` as a tiebreaker. More complex nested conflicts are
resolved by scanning the existing items in the origin gap and choosing the same
conflict-free left neighbor on every replica. The goal is not to determine which
user edited first, because concurrent operations have no reliable physical
order. The goal is to ensure that every replica chooses the same order from the
same set of items.

As a result, if all replicas receive the same concurrent insertions, they will
eventually converge, even if the updates arrive in different orders.

=== Remote Deletions

Remote deletions use the stable id range produced by the original local
deletion, not a visible index range. A delete message contains a client id, a
starting clock, and a length, which identify the historical items that must be
marked as deleted.

On the receiving replica, this range is resolved through the struct store. If
the referenced inserted items are not known yet, the deletion cannot be applied
immediately and is kept pending. Once the items are available, the receiver
splits boundary items if necessary and marks the corresponding range as deleted.

This makes remote deletion independent of the receiver's current visible text.
Even if replicas temporarily have different document contents or item handles,
the same id range still refers to the same historical content.

== Synchronization

Synchronization is separated from the transport layer. The CRDT does not care
whether update bytes are sent through WebRTC, WebSocket, local storage etc. The
synchronization API only needs two messages: a state vector and an update.

=== State Vectors

A state vector is a compact summary of what a replica already knows. It stores,
for each client, the next clock that this replica expects from that client. For
example, if a replica has items from client `7` covering clocks `0..12`, then
its state vector contains the next item it expects: `"client 7": 13`

This means that clocks below `13` from client `7` are already known, and clock
`13` is the next missing position in that client's history.

State vectors are small because they depend on the number of clients, not on the
size of the document. The implementation builds this summary directly from
`StructStore`.

=== Updates

An update is encoded relative to a target state vector. If no target state
vector is provided, the implementation encodes the whole known document state.
If a target state vector is provided, the implementation sends only the item
ranges that the target replica is missing.

For each client, the encoder finds the first item whose clock range is not fully
covered by the target state vector. If the target already has the first part of
a text item, the update can start in the middle of that item and send only the
remaining suffix. This is possible because each text item owns a contiguous
clock range and stores its logical length.

#figure(
  protocol-diagrams.update-layout,
  caption: [Binary update layout],
) <fig:update-layout>

Encoding updates as JSON would be inefficient because collaborative text data
contains a large amount of repeated metadata. General binary formats such as
Cap'n Proto are more compact, but a custom binary format can reduce metadata
even further by exploiting the structure of CRDT updates
@crdt-reducing-metadata-overhead.

As shown in @fig:update-layout, an update consists of a small envelope, changed
item blocks, and a delete set. The envelope contains magic bytes and a version
number. Integer values are encoded using unsigned LEB128-style variable-length
integers, following the same general approach as the WebAssembly binary format
@webassembly-binary-values.

Changed items are grouped by client, and their fields are written in columns
rather than as independent records. This column-oriented layout makes repeated
metadata easier to compress.

For example, suppose one update contains `42` consecutive single-character items created by client `7`. A straightforward item-by-item encoding that stores both `ClientId` and `Clock` as fixed-width 64-bit values for every item would use $42 dot (64 + 64) / 8 = 672$ bytes just for item ids.

The implementation instead writes one client block:

```text
client id: 7
item count: 42
first clock: C
item columns: ...
```

The client id is stored once, and all items inside the block inherit that client. Their clocks are reconstructed from the first clock and the item-length column. For single-character items, the length column contains the same value repeated 42 times. This can be represented with run-length encoding as one run @rle[pp. 20-24], for example `(value: 1, run_len: 42)`.

Because small integers are compact under unsigned LEB128 encoding, this id encoding occupies around 5 bytes. The exact saving depends on the data and column overhead, so the encoder uses run-length encoding only when it is smaller than the raw varint column.

Deletion information is encoded separately as a delete set. The delete set
groups deleted clock ranges by client, so multiple adjacent deletions can be
represented as ranges instead of individual item ids.

This section does not describe the complete byte layout. The important design
point is that synchronization is based on stable item ids and state vectors, and
this metadata can be encoded compactly.

=== Out-of-Order Delivery

Updates may arrive before their dependencies. For example, a replica may receive
a deletion for a text range before it has received the insertion that created
that range. Similarly, a remote item may refer to left or right origins that are
not known locally yet.

When this happens, the implementation does not discard the update immediately.
It stores the update in a bounded pending-update buffer. After any later update
is integrated successfully, pending updates are retried. Once their dependencies
are available, they can be applied normally.

This means that the transport layer does not need to provide causal delivery.
Messages may be delayed, duplicated, or delivered in a different order from the
one in which they were created. As long as all replicas eventually receive the
same set of updates, the CRDT state can still converge.

== Rich Text Formatting

Formatting is represented inside the same CRDT sequence as text. The
implementation does not maintain a separate interval tree for styles. Instead,
it inserts non-countable format items into the linked list. These items have ids
and origins like text items, so they can be synchronized and ordered using the
same CRDT machinery, but they do not contribute to the visible text length.

A format item changes the active value of one attribute key for the text that
follows it. The value can be a string, which sets the attribute, or `null`,
which clears it. For example, applying `bold=true` to `"world"` in
`"Hello, world"` is represented by placing a marker before the formatted range
and a clearing marker after it:

`[Hello, ] [bold=true] [world] [bold=null]`

#figure(
  table(
    columns: (0.7fr, 1fr, 1.65fr, 1.05fr),
    align: horizon,
    table.header([handle], [kind], [content slice], [visible]),
    [`h0`], [string], [`bytes[0..5] = "Hello"`], [yes],
    [`h2`], [string], [`bytes[11..12] = ","`], [yes],
    [`h1`], [string], [`bytes[5..6] = " "`], [yes],

    [`h4`],
    [format],
    [`key = bytes[12..16] = "bold", value = bytes[16..20] = "true"`],
    [no],

    [`h3`], [string], [`bytes[6..11] = "world"`], [yes],
    [`h5`], [format], [`key = bytes[20..24] = "bold", value=null`], [no],
  ),
  caption: [Item metadata after formatting a range],
) <fig:attribute-marker-table>

#figure(
  diagrams.attribute-markers,
  caption: [Formatting markers in the item sequence],
) <fig:attribute-markers>

@fig:attribute-marker-table shows the item metadata for this example, while
@fig:attribute-markers shows the same state as an ordered sequence. Format
markers are ordinary CRDT items with ids and byte slices, but they are skipped
when producing plain visible text.

Rendering walks the sequence from left to right. When it encounters a format
item, it updates the currently active attributes. When it encounters a
non-deleted string item, it emits the text with the attributes that are active
at that point. The same traversal can therefore produce plain text by ignoring
active attributes, or attributed delta operations by attaching the active
attributes to each emitted text fragment.

Restore markers are needed when formatting only a range. If an attribute had a
previous value after the range, the implementation restores that value;
otherwise it inserts a `null` marker to clear the attribute. This allows
overlapping formatting to behave naturally. For example, applying blue
formatting to the middle of an already red range affects only the nested range,
while the text after it returns to red:

#figure(
  align(center)[
    #grid(
      columns: (auto, auto, auto),
      column-gutter: 0.8em,
      align: horizon,
      box(inset: 3pt, stroke: red)[#text(fill: red)[abcd]],
      $arrow.r.long$,
      box(inset: 3pt, stroke: red)[
        #text(fill: red)[a]
        #box(inset: 3pt, stroke: blue)[#text(fill: blue)[bc]]
        #text(fill: red)[d]
      ],
    )
  ],
  caption: [Restoring formatting after applying a nested range],
)

Formatting markers may become redundant after later edits. For example, the
formatted range may be deleted, or two neighboring markers may set the same
value. The implementation therefore provides `compact()`, which removes
redundant format markers and joins adjacent string items when this is safe.
Compaction is an explicit maintenance operation rather than a step performed
after every edit, because local editing should remain fast even if the internal
representation is not immediately minimal.

== WebAssembly Interface

The WebAssembly interface is intentionally minimal and consists of raw exported
functions. JavaScript code does not access Zig structs directly. Instead, it
creates a document and receives an opaque handle, which is passed back to
exported functions.

Text and update data cross the boundary as pointer-and-length pairs because raw
WebAssembly exports cannot receive JavaScript strings directly
@mdn-wasm-text-format. JavaScript first copies the bytes into WebAssembly
memory, then passes the pointer and length to the exported function. Output data
is returned the same way, and the wrapper exposes allocation and free functions
so JavaScript can manage these temporary buffers.

Operations that can fail return compact integer error codes at the WebAssembly
boundary. Internally, the Zig implementation still uses error unions, but the
exported API converts them into a representation that is simple to handle from
JavaScript.

== Testing and Validation

This implementation does not include a formal machine-checked proof. Instead, it
is validated with behavior-focused tests that exercise the main correctness
properties expected from the CRDT model.

The lowest-level tests are unit tests. They cover utility behavior used by
higher-level algorithms.

The most important tests are randomized fuzz tests. They create several document
replicas, apply random operations, and then check that all replicas eventually
render the same document. These tests do not prove correctness for every
possible execution, but they are effective at exposing mistakes.

== Limitations

The implementation is intentionally narrower than production CRDT libraries such
as Yjs or Automerge. The main limitations are:

- *Single text document.* The implementation focuses on one collaborative text
  value. It does not provide general CRDT maps, arrays, XML-like structures,
  subdocuments, snapshots, undo management, or awareness state.

- *Tombstone growth.* Deleted items remain in the structure because remote
  operations may still refer to their ids. The implementation provides
  `compact()` for some safe local cleanup, but it does not implement full CRDT
  garbage collection.

- *Simple delete synchronization.* Updates currently include the known delete
  set. This keeps deletion idempotent and easy to integrate, but it can be
  inefficient for documents with large deletion histories.

- *Bounded pending updates.* Out-of-order updates are stored in a bounded
  pending buffer. This prevents unbounded memory growth, but retrying is
  coarse-grained and not indexed by exact missing dependencies.

- *Unicode scalar indexing.* Public indexes are based on Unicode scalar values
  over valid UTF-8, not grapheme clusters @grapheme-clustering.

- *Limited rich-text model.* Attributes are represented only as string values or
  `null`. This is enough for simple metadata such as bold, colors, and links,
  but it is not a complete rich-text document model. Format attribute values are
  also duplicated in the shared buffer rather than interned in a key/value pool.

- *Explicit size and format checks.* Invalid UTF-8, malformed updates,
  unsupported versions, trailing bytes, and values that exceed supported integer
  ranges are rejected. Very large documents may therefore require chunking or
  application-level handling.

- *Primitive position cache.* Translation from visible indexes to internal
  positions uses only a simple last-cursor cache. This helps with nearby
  sequential edits, but it is not a full indexing structure, so random access in
  large documents may still require linear traversal.

#bibliography("./bib.yml")
