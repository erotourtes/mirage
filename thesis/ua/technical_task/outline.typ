#import "../lib.typ": outline_page_frame

#let technical-task-labels = (
  start-page: <technical-task-start-metadata-label>,
  end-page: <technical-task-end-metadata-label>,
  header: <technical-task-outline>,
)

#let technical_task_outline_heading(level: 1, body) = [#heading(
    level: 1,
  )[#body] #technical-task-labels.header]


#let technical_task_sheet_footer(
  document-code: [todo],
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
        #text(size: 14pt)[#document-code]
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

#let technical_task_page_frame(body) = [
  #outline_page_frame(
    footer: technical_task_sheet_footer(),
  )[
    #body
    #metadata("end") #technical-task-labels.end-page
  ]
]

#let outline_entry_row(entry) = [
  #let page-number = counter(page).at(entry.location()).first()
  #link(
    entry.location(),
  )[
    #grid(
      columns: (auto, 1fr, auto),
      column-gutter: 1.6mm,
      [#pad(left: 11mm * calc.max(entry.level - 1, 0))[
        #entry.body
      ]],
      [#box(width: 100%, clip: true)[#repeat()[.]]],
      [#page-number],
    )
  ]
]

#let outline_entry_gap(entries, index) = {
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

#let outline_stamp(
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
        #text()[Технічне завдання]
      ]
    ],

    table.cell(colspan: 3)[
      #text()[Літ.]
    ],
    [#text()[Аркуш]],
    [#text()[Аркушів]],

    table.cell(colspan: 2)[#text(size: 9pt)[Перевірив]],
    [#text(size: 7pt)[#reviewed-by]],
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

#let technical_task_outline_page(
  topic: none,
  group: none,
  document-code: [todo],
  implemented-by: [todo],
  reviewed-by: [todo],
  norm-controller: [],
  approved-by: [],
) = context {
  counter(page).update(1)

  let entries = query(selector(heading).and(technical-task-labels.header))
  let sheet-count = context {
    let starts = query(technical-task-labels.start-page)
    let ends = query(technical-task-labels.end-page)

    if starts.len() == 0 or ends.len() == 0 {
      [??]
    } else {
      let start-page = starts.first().location().page()
      let end-page = ends.last().location().page()

      end-page - start-page + 1
    }
  }

  outline_page_frame(
    footer: outline_stamp(
      topic: topic,
      group: group,
      document-code: document-code,
      sheet-number: [1],
      sheet-count: [#sheet-count],
      implemented-by: implemented-by,
      reviewed-by: reviewed-by,
      norm-controller: norm-controller,
      approved-by: approved-by,
    ),
  )[
    #metadata("start") #technical-task-labels.start-page

    #align(center)[ЗМІСТ]
    #v(7mm)

    #for (index, entry) in entries.enumerate() [
      #outline_entry_row(entry)
      #v(outline_entry_gap(entries, index))
    ]
  ]
}
