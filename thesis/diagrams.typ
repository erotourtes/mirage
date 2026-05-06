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

#let clock-event(pos, name) = node(
  pos,
  [],
  name: name,
  radius: 1.7mm,
  stroke: 1pt,
  fill: rgb("#ead7cf"),
)

#let clock-label(pos, body) = label-node(pos, text(size: 8pt, body))

#let range-box(body, fill: rgb("#ead7cf")) = box(
  inset: (x: 5pt, y: 3pt),
  radius: 2pt,
  stroke: 0.8pt,
  fill: fill,
  body,
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
  lamport-clocks: diagram(
    spacing: (14mm, 11mm),
    edge-stroke: 1pt,
    label-size: 9pt,

    label-node((-0.7, 0), [X]),
    label-node((-0.7, 1), [Y]),
    label-node((-0.7, 2), [Z]),

    clock-event((1.6, 0), <a1>),
    clock-event((2.4, 0), <a2>),
    clock-event((3.6, 0), <a3>),

    clock-event((3.2, 1), <b1>),
    clock-event((4.0, 1), <b2>),

    clock-event((0, 2), <c1>),
    clock-event((0.8, 2), <c2>),
    clock-event((4.8, 2), <c3>),

    edge(<a1>, <a2>, "-|>"),
    edge(<a2>, <a3>, "-|>"),
    edge(<b1>, <b2>, "-|>"),
    edge(<c1>, <c2>, "-|>"),
    edge(<c2>, <c3>, "-|>"),

    edge(
      <c2>,
      <a3>,
      [$m_1$, $t=2$],
      "-|>",
      label-side: center,
      label-pos: 0.15,
    ),
    edge(<a2>, <b1>, [$m_2$, $t=2$], "-|>", label-side: center, label-pos: 0.3),
    edge(<b2>, <c3>, [$m_3$, $t=4$], "-|>", label-side: center, label-pos: 0.3),

    clock-label((1.6, -0.34), [$x$: local\ $C=1$]),
    clock-label((2.4, -0.34), [send\ $C=2$]),
    clock-label((3.6, -0.34), [receive\ $max(2, 2)+1=3$]),

    clock-label((3.2, 1.34), [receive\ $max(0, 2)+1=3$]),
    clock-label((4.0, 0.6), [send\ $C=4$]),

    clock-label((0, 2.34), [local\ $C=1$]),
    clock-label((0.8, 2.34), [$y$: send\ $C=2$]),
    clock-label((4.8, 2.34), [receive\ $max(2, 4)+1=5$]),
  ),
  delete-set-merge: stack(
    dir: ttb,
    spacing: 0.9em,
    align(center)[
      deleted ranges before compaction (clock, len)
    ],
    stack(
      dir: ltr,
      spacing: 0.6em,
      range-box($(0, 2)$),
      range-box($(13, 1)$),
      range-box($(12, 1)$),
      range-box($(11, 1)$),
      range-box($(2, 9)$),
    ),
    text(size: 9pt, font: "DejaVu Sans Mono")[sortAndMerge],
    stack(
      dir: ltr,
      spacing: 0.6em,
      range-box($(0, 14)$, fill: rgb("#d9ead3")),
    ),
  ),
)
