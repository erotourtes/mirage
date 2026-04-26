#import "lib.typ": standard_page_frame

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
  implementedBy: [todo],
  examinedBy: [todo],
) = {
  let first_table_entries = (
    (
      topic: [#topic\ Технічне завдання],
      code: [todo],
      sheets: [todo],
    ),
    (
      topic: [#topic\ Пояснювальна записка],
      code: [todo],
      sheets: [todo],
    ),
    (
      topic: [#topic\ Компоненти застосунка\ (структурна схема)],
      code: [todo],
      sheets: [todo],
    ),
    (
      topic: [#topic\ Діаграма сутність-зв'язок\ (функціональна схема)],
      code: [todo],
      sheets: [todo],
    ),
    (
      topic: [#topic\ Алгоритм дій застосунку\ (принципова схема)],
      code: [todo],
      sheets: [todo],
    ),
    (
      topic: [#topic\ Текст програмного коду],
      code: [todo],
      sheets: [todo],
    ),
  )

  standard_page_frame[
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
      )[todo]],
      [], [], [], [], [],
      [Зм.], [Лист], [#text(size: 10.5pt)[№ докум.]], [Підпис], [Дата],

      table.cell(colspan: 2)[#text(weight: "bold")[Розроб.]],
      [#implementedBy],
      [],
      [],
      table.cell(
        rowspan: 3,
        align: center + horizon,
        inset: 7mm,
      )[#text(style: "italic")[#topic\ Технічне завдання]],
      table.cell(colspan: 3)[Літ.], [Аркуш], [Аркушів],
      table.cell(colspan: 2)[#text(weight: "bold")[Перевір.]],
      [#examinedBy],
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
