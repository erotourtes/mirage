#import "../lib.typ": standard_page_frame

#let report-outline-label = label("report-outline")

#let report_outline_heading(level: 1, numbered: true, body) = {
  if level == 1 and numbered {
    [= #body <report-outline>]
  } else if level == 2 and numbered {
    [== #body <report-outline>]
  } else if level == 3 and numbered {
    [=== #body <report-outline>]
  } else if level == 1 {
    [#heading(level: 1, numbering: none)[#body] <report-outline>]
  } else if level == 2 {
    [#heading(level: 2, numbering: none)[#body] <report-outline>]
  } else if level == 3 {
    [#heading(level: 3, numbering: none)[#body] <report-outline>]
  } else {
    panic("report_outline_heading currently supports levels 1 to 3")
  }
}

#let report_page_frame(footer: [], body: []) = {
  standard_page_frame()[
    #box(width: 100%, height: 100%, stroke: 2pt)[
      #grid(
        rows: (1fr, auto),
        row-gutter: 0pt,
        [
          #pad(x: 12mm, top: 12mm, bottom: 8mm)[
            #body
          ]
        ],
        [#footer],
      )
    ]
  ]
}

#let report_sheet_footer(
  document-code: [todo],
  sheet-number: [1],
) = [
  #set text(size: 10.5pt)
  #table(
    columns: (7mm, 10mm, 23mm, 15mm, 10mm, 1fr, 13mm),
    rows: (5mm, 5mm, 5mm),
    stroke: 1.2pt,
    inset: (x: 0.8mm, y: 0.4mm),
    align: horizon + center,

    [], [], [], [], [],
    table.cell(rowspan: 3, align: center + horizon)[
      #text(size: 14pt)[#document-code]
    ],
    [#text()[Арк.]],

    [], [], [], [], [],
    table.cell(rowspan: 2)[#sheet-number],

    [#text()[Зм.]],
    [#text()[Арк.]],
    [#text()[№ докум.]],
    [#text()[Підпис]],
    [#text()[Дата]],
  )
]

#let report_outline_entry_row(entry) = [
  #let page-number = counter(page).at(entry.location()).first()
  #let heading-number = if entry.numbering == none {
    []
  } else {
    [#numbering(entry.numbering, ..counter(heading).at(entry.location())) ]
  }
  #link(entry.location())[
    #grid(
      columns: (auto, 1fr, auto),
      column-gutter: 1.6mm,
      [#pad(left: 11mm * calc.max(entry.level - 1, 0))[
        #heading-number #entry.body
      ]],
      [#box(width: 100%, clip: true)[#repeat()[.]]],
      [#page-number],
    )
  ]
]

#let report_outline_entry_gap(entries, index) = {
  if index + 1 >= entries.len() {
    0mm
  } else {
    let entry = entries.at(index)
    let next = entries.at(index + 1)

    if next.level > entry.level {
      2mm
    } else if entry.level == 1 {
      3mm
    } else {
      2mm
    }
  }
}

#let report_outline_stamp(
  topic: none,
  group: none,
  document-code: [todo],
  sheet-number: [1],
  sheet-count: [1],
  implemented-by: [todo],
  reviewed-by: [todo],
  norm-controller: [],
  approved-by: [],
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
      #text(size: 14pt)[#document-code]
    ],

    [], [], [], [], [],

    [],
    [],
    [#text()[№ докум.]],
    [#text()[Підпис]],
    [#text()[Дата]],

    table.cell(colspan: 2)[#text()[Розробив]],
    [#text(size: 8pt)[#implemented-by]],
    [],
    [],

    table.cell(rowspan: 5, align: center + horizon, inset: 2.5mm)[
      #align(center)[
        #text(weight: "bold")[#topic]
        #v(1.5mm)
        #text()[Пояснювальна записка]
      ]
    ],

    table.cell(colspan: 3)[#text()[Літ.]],
    [#text()[Аркуш]],
    [#text()[Аркушів]],

    table.cell(colspan: 2)[#text(size: 9pt)[Перевірив]],
    [#text(size: 8pt)[#reviewed-by]],
    [],
    [],
    [], [], [],
    [#sheet-number],
    [#sheet-count],

    table.cell(colspan: 2)[], [], [], [],
    table.cell(rowspan: 3, colspan: 5, align: center + horizon, inset: 1.5mm)[
      #text()[НТУУ КПІ ім. Ігоря\ Сікорського, ФІОТ, #group]
    ],

    table.cell(colspan: 2)[#text()[Н. Контр.]],
    [#text(size: 8pt)[#norm-controller]],
    [],
    [],

    table.cell(colspan: 2)[#text(size: 9pt)[Затвердив]],
    [#text(size: 8pt)[#approved-by]],
    [],
    [],
  )
]

#let report_outline_page(
  topic: none,
  group: none,
  document-code: [todo],
  sheet-number: [1],
  sheet-count: [1],
  implemented-by: [todo],
  reviewed-by: [todo],
  norm-controller: [],
  approved-by: [],
) = context {
  counter(page).update(1)
  let entries = query(selector(heading).and(report-outline-label))

  report_page_frame(
    footer: report_outline_stamp(
      topic: topic,
      group: group,
      document-code: document-code,
      sheet-number: sheet-number,
      sheet-count: sheet-count,
      implemented-by: implemented-by,
      reviewed-by: reviewed-by,
      norm-controller: norm-controller,
      approved-by: approved-by,
    ),
    body: [
      #align(center)[ЗМІСТ]
      #v(7mm)

      #for (index, entry) in entries.enumerate() [
        #report_outline_entry_row(entry)
        #v(report_outline_entry_gap(entries, index))
      ]
    ],
  )
}
