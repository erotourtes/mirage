#import "@preview/fletcher:0.5.8": diagram, edge, node

#let ot-node(pos, name) = node(
  pos,
  [],
  name: name,
  radius: 1.5mm,
  stroke: 1pt,
  fill: rgb("#ead7cf"),
)

#let ot-diagram(..items) = diagram(
  spacing: (9mm, 9mm),
  edge-stroke: 1pt,
  label-size: 13pt,
  ..items,
)

#let label-node(pos, body) = node(
  pos,
  body,
  stroke: none,
  fill: none,
)


#let diagrams = (
  ot-basic: ot-diagram(
    ot-node((1, 0), <s0>),
    ot-node((0, 1), <s1>),
    ot-node((2, 1), <s2>),

    edge(<s0>, <s1>, $a$, "-|>"),
    edge(<s0>, <s2>, $b$, "-|>"),
  ),
  ot-transformed: ot-diagram(
    ot-node((1, 0), <s0>),
    ot-node((0, 1), <s1>),
    ot-node((2, 1), <s2>),
    ot-node((1, 2), <s3>),

    edge(<s0>, <s1>, $a$, "-|>"),
    edge(<s0>, <s2>, $b$, "-|>"),

    edge(<s1>, <s3>, $b'$, "--|>", label-side: right),
    edge(<s2>, <s3>, $a'$, "--|>", label-side: left),
  ),
  ot-extended: ot-diagram(
    ot-node((2, 0), <s0>),
    ot-node((1, 1), <s1>),
    ot-node((3, 1), <s2>),
    ot-node((0, 2), <s3>),
    ot-node((2, 2), <s4>),
    ot-node((1, 3), <s5>),
    ot-node((0, 4), <s6>),

    edge(<s0>, <s1>, $a$, "-|>"),
    edge(<s0>, <s2>, $b$, "-|>"),

    edge(<s1>, <s3>, $c$, "-|>", label-pos: 0.42),
    edge(<s2>, <s4>, $a'$, "--|>", label-pos: 0.42),

    edge(<s3>, <s5>, $b'$, "--|>"),
    edge(<s5>, <s6>, $e$, "-|>"),
  ),
  subset-lattice: ot-diagram(
    // nodes
    ot-node((1.5, 0), <xyz>),

    ot-node((0.5, 1), <xy>),
    ot-node((1.5, 1), <xz>),
    ot-node((2.5, 1), <yz>),

    ot-node((0, 2), <x>),
    ot-node((1.5, 2), <y>),
    ot-node((3, 2), <z>),

    ot-node((1.5, 3), <empty>),

    // labels
    label-node((1.5, -0.38), ${x, y, z}$),

    label-node((0.3, 0.62), ${x, y}$),
    label-node((1.5, 0.62), ${x, z}$),
    label-node((2.7, 0.62), ${y, z}$),

    label-node((-0.15, 1.62), ${x}$),
    label-node((1.5, 1.62), ${y}$),
    label-node((3.15, 1.62), ${z}$),

    label-node((1.5, 3.38), $emptyset.rev$),

    // cover edges
    edge(<empty>, <x>, "-"),
    edge(<empty>, <y>, "-"),
    edge(<empty>, <z>, "-"),

    edge(<x>, <xy>, "-"),
    edge(<x>, <xz>, "-"),

    edge(<y>, <xy>, "-"),
    edge(<y>, <yz>, "-"),

    edge(<z>, <xz>, "-"),
    edge(<z>, <yz>, "-"),

    edge(<xy>, <xyz>, "-"),
    edge(<xz>, <xyz>, "-"),
    edge(<yz>, <xyz>, "-"),
  ),
  three-way-merge: ot-diagram(
    spacing: (12mm, 10mm),

    // main line
    ot-node((0, 1), <start>),
    ot-node((1.4, 1), <base>),
    ot-node((4.0, 1), <upper>),
    ot-node((6.6, 1), <merged>),

    // diverging lower branch
    ot-node((2.4, 2.2), <lower1>),
    ot-node((4.0, 2.2), <lower2>),
    ot-node((5.6, 2.2), <lower3>),

    label-node((1.4, 0.6), [Base]),
    label-node((4.0, 0.6), [Theirs]),
    label-node((4.0, 1.8), [Ours]),
    label-node((6.6, 0.6), [Merged]),

    // edges
    edge(<start>, <base>, "-|>"),
    edge(<base>, <upper>, "-|>"),
    edge(<upper>, <merged>, "-|>"),

    edge(<base>, <lower1>, "-|>"),
    edge(<lower1>, <lower2>, "-|>"),
    edge(<lower2>, <lower3>, "-|>"),
    edge(<lower3>, <merged>, "-|>"),
  ),
)
