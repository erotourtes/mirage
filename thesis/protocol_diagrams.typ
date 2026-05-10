#import "@preview/fletcher:0.5.8": diagram, edge, node

#let proto-field(title, body, fill: rgb("#f7f3ef"), width: auto) = box(
  width: width,
  inset: (x: 5pt, y: 4pt),
  stroke: 0.75pt,
  fill: fill,
)[
  #text(size: 7pt, weight: "bold")[#title]
  #linebreak()
  #text(size: 6pt)[#body]
]

#let proto-row(..fields) = stack(
  dir: ltr,
  spacing: 0pt,
  ..fields,
)

#let proto-section(title, body) = stack(
  dir: ttb,
  spacing: 0.25em,
  align(left)[#text(size: 8pt, weight: "bold")[#title]],
  box(width: 100mm, align(left)[
    #body
  ]),
)

#let protocol-diagrams = (
  update-layout: diagram(
    debug: true,
    spacing: (0mm, 0mm),

    node(
      (0mm, 0mm),
      name: <update>,
      [
        #proto-section(
          [update],
          proto-row(
            proto-field([magic], [`"MYPEACE"`], fill: rgb("#ead7cf")),
            proto-field([version], [`1`], fill: rgb("#ead7cf")),
            proto-field(
              [changed clients],
              [`varuint count`],
              fill: rgb("#d9eaf7"),
            ),
            proto-field(
              [client blocks],
              [`repeated count times`],
              fill: rgb("#d9eaf7"),
              width: 112pt,
            ),
            proto-field(
              [delete set],
              [`grouped by client`],
              fill: rgb("#d9ead3"),
              width: 94pt,
            ),
          ),
        )
      ],
    ),

    node((rel: (-20mm, -20mm), to: <update>), name: <client-block>, [
      #proto-section([client block], proto-row(
        proto-field([client id], [`varuint`], fill: rgb("#d9eaf7")),
        proto-field([item count], [`varuint`], fill: rgb("#d9eaf7")),
        proto-field([first clock], [`varuint`], fill: rgb("#d9eaf7")),
        proto-field(
          [item columns],
          [`one payload per column`],
          fill: rgb("#f7f3ef"),
          width: 148pt,
        ),
      )),
    ]),

    node((rel: (-20mm, -40mm), to: <update>), name: <item-columns>, [
      #proto-section([item columns], proto-row(
        proto-field([lengths], [`varints`], fill: rgb("#f7f3ef")),
        proto-field(
          [left origins],
          [`kind column + ids`],
          fill: rgb("#f7f3ef"),
          width: 88pt,
        ),
        proto-field(
          [right origins],
          [`kind column + ids`],
          fill: rgb("#f7f3ef"),
          width: 88pt,
        ),
        proto-field(
          [content tags],
          [`string / format`],
          fill: rgb("#f7f3ef"),
          width: 78pt,
        ),
        proto-field(
          [string data],
          [`lens + bytes`],
          fill: rgb("#f7f3ef"),
          width: 76pt,
        ),
        proto-field(
          [format data],
          [`keys + values`],
          fill: rgb("#f7f3ef"),
          width: 76pt,
        ),
      )),
    ]),

    node((rel: (30mm, -60mm), to: <update>), name: <delete-set>, [
      #proto-section([delete set], proto-row(
        proto-field(
          [delete clients],
          [`varuint count`],
          fill: rgb("#d9ead3"),
          width: 88pt,
        ),
        proto-field(
          [delete client block],
          [`client id, range count`],
          fill: rgb("#d9ead3"),
          width: 120pt,
        ),
        proto-field(
          [delete ranges],
          [`(clock, len) repeated`],
          fill: rgb("#d9ead3"),
          width: 120pt,
        ),
      )),
    ]),

    edge(
      (15mm, -5.7mm),
      (15mm, -11.7mm),
      (-53mm, -11.7mm),
      "-|>",
      layer: 10,
      snap-to: none,
    ),
    edge(
      (0mm, -22.2mm),
      (0mm, -32mm),
      (-52mm, -32mm),
      "-|>",
      layer: 10,
      snap-to: none,
    ),
    edge(
      (68mm, -1mm),
      (89mm, -1mm),
      (89mm, -52mm),
      (-6mm, -52mm),
      "-|>",
      layer: 10,
      snap-to: none,
    ),
  ),
)
