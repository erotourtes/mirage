
#let footer_f2a(
  document_code: none,
) = context {
  [
    #set text(size: 10.5pt)
    #table(
      columns: (7mm, 10mm, 23mm, 15mm, 10mm, 1fr, 10mm),
      rows: (5mm, 5mm, 5mm),
      stroke: 1.2pt,
      inset: (x: 0.8mm, y: 0.4mm),
      align: horizon + center,

      [], [], [], [], [],
      table.cell(rowspan: 3, align: center + horizon)[
        #text(size: 14pt)[#document_code]
      ],
      [#text()[Арк.]],

      [], [], [], [], [],
      table.cell(rowspan: 2)[#counter(page).display()],

      [#text()[Зм.]],
      [#text()[Арк.]],
      [#text()[№ докум.]],
      [#text()[Підпис]],
      [#text()[Дата]],
    )
  ]
}

#let footer_f2(
  document_name: none,
  topic: none,
  group: none,
  document_code: none,
  sheet_number: none,
  sheet_count: none,
  implemented_by: none,
  reviewed_by: none,
  norm_controller: none,
  approved_by: none,
) = [
  #set text(size: 10.5pt)
  #table(
    columns: (7mm, 10mm, 23mm, 15mm, 10mm, 70mm, 5mm, 5mm, 5mm, 17mm, 1fr),
    rows: range(8).map(_ => 5mm),
    stroke: 1.2pt,
    inset: (x: 0.8mm, y: 0.4mm),
    align: horizon + center,

    [], [], [], [], [],
    table.cell(colspan: 6, rowspan: 3, align: center + horizon)[
      #text(size: 14pt)[#document_code]
    ],

    [], [], [], [], [],

    [],
    [],
    [#text()[№ докум.]],
    [#text()[Підпис]],
    [#text()[Дата]],

    table.cell(colspan: 2)[#text()[Розробив]],
    [#text(size: 8pt)[#implemented_by]],
    [],
    [],

    table.cell(rowspan: 5, align: center + horizon, inset: 2.5mm)[
      #align(center)[
        #text(weight: "bold")[#topic]
        #v(1.5mm)
        #text()[#document_name]
      ]
    ],

    table.cell(colspan: 3)[
      #text()[Літ.]
    ],
    [#text()[Аркуш]],
    [#text()[Аркушів]],

    table.cell(colspan: 2)[#text(size: 9pt)[Перевірив]],
    [#text(size: 7pt)[#reviewed_by]],
    [],
    [],
    [], [], [],
    [#sheet_number],
    [#sheet_count],

    table.cell(colspan: 2)[], [], [], [],
    table.cell(rowspan: 3, colspan: 5, align: center + horizon, inset: 1.5mm)[
      #text()[НТУУ КПІ ім. Ігоря\ Сікорського, ФІОТ, #group]
    ],

    table.cell(colspan: 2)[#text()[Н. Контр.]],
    [#text(size: 8pt)[#norm_controller]],
    [],
    [],

    table.cell(colspan: 2)[#text(size: 9pt)[Затвердив]],
    [#text(size: 8pt)[#approved_by]],
    [],
    [],
  )
]
