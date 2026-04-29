#import "../lib/lib.typ": full_document_code
#import "../lib/page.typ": standard_page

#let header_cell(body) = table.cell(align: center + horizon)[
  #{
    set par(leading: 0.65em)
    body
  }
]

#let first_table_row(topic, code, sheets, format: [A4]) = (
  [],
  [#align(center)[#text(weight: "bold")[#format]]],
  [#text(weight: "bold")[#code]],
  [#topic],
  [#align(center)[#sheets]],
  [],
  [],
)

#let first_table_empty_row = (
  [],
  [],
  [],
  [],
  [],
  [],
  [],
)

#let first_table_rows(entries) = {
  let generated = ()
  generated += first_table_empty_row
  generated += first_table_empty_row
  for (i, entry) in entries.enumerate() {
    generated += first_table_row(entry.topic, entry.code, entry.sheets)
    let repeat = if (i < 2) { 4 } else { 5 }
    for i in range(1, repeat + 1) {
      generated += first_table_empty_row
    }
  }
  generated
}

#let album_description_page(
  topic: [],
  group: [],
  codes: (:),
  implemented_by: [todo],
  examined_by: [todo],
) = {
  let first_table_entries = (
    (
      topic: [#topic\ #codes.technical_task.long_form],
      code: full_document_code(codes.technical_task),
      sheets: [todo],
    ),
    (
      topic: [#topic\ #codes.report.long_form],
      code: full_document_code(codes.report),
      sheets: [todo],
    ),
    (
      topic: [#topic\ #codes.d1.long_form],
      code: full_document_code(codes.d1),
      sheets: [todo],
    ),
    (
      topic: [#topic\ #codes.d2.long_form],
      code: full_document_code(codes.d2),
      sheets: [todo],
    ),
    (
      topic: [#topic\ #codes.d3.long_form],
      code: full_document_code(codes.d3),
      sheets: [todo],
    ),
    (
      topic: [#topic\ #codes.d4.long_form],
      code: full_document_code(codes.d4),
      sheets: [todo],
    ),
  )

  standard_page[
    #set text(size: 11.5pt)
    #set par(leading: 0.6em)
    #table(
      columns: (12mm, 10mm, 47mm, 60mm, 12mm, 14mm, 30mm),
      rows: (
        25mm,
        ..range(30).map(_ => 5.3mm),
      ),
      stroke: 0.45pt,
      inset: (x: 1.5mm, y: 1.3mm),
      align: top + left,

      header_cell[#rotate(-90deg)[справки]],
      header_cell[#rotate(-90deg)[Формат]],
      header_cell[#text(weight: "bold")[Значення]],
      header_cell[#text(weight: "bold")[Найменування]],
      header_cell[#rotate(-90deg)[Кіл.\ листів]],
      header_cell[#rotate(-90deg)[№\ екземплярів]],
      header_cell[#text(weight: "bold")[Додаток]],

      [], [], [], [Документація загальна\ Знову розроблена], [], [], [],
      ..first_table_rows(first_table_entries),
    )
    #v(-4.9mm)
    #table(
      columns: (12mm, 10mm, 18mm, 15mm, 10mm, 70mm, 5mm, 5mm, 5mm, 17mm, 1fr),
      rows: (5mm, 5mm, 5mm, 5mm, 5mm, 16mm),
      stroke: 1.5pt,
      inset: (x: 1.2mm, y: 0.6mm),
      align: horizon + left,

      [], [], [], [], [],
      table.cell(rowspan: 3, colspan: 6, align: center)[#text(
        size: 17pt,
        weight: "bold",
        style: "italic",
      )[#full_document_code(codes.technical_task)]],
      [], [], [], [], [],
      [Зм.], [Лист], [#text(size: 10.5pt)[№ докум.]], [Підпис], [Дата],

      table.cell(colspan: 2)[#text(weight: "bold")[Розроб.]],
      [#implemented_by],
      [],
      [],
      table.cell(
        rowspan: 3,
        align: center + horizon,
        inset: 7mm,
      )[#text(style: "italic")[#topic\ #codes.technical_task.long_form]],
      table.cell(colspan: 3)[Літ.], [Аркуш], [Аркушів],
      table.cell(colspan: 2)[#text(weight: "bold")[Перевір.]],
      [#examined_by],
      [], [], [], [], [], [1], [1],

      table.cell(colspan: 2)[],
      [], [], [],
      table.cell(colspan: 5, align: center)[#text(
        weight: "bold",
        style: "italic",
      )[НТУУ "КПІ" ФІОТ\ #group]],
    )
  ]
}
