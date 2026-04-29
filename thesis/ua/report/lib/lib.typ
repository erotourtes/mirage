
#import "../../lib/footer.typ": footer_f2a
#import "../../lib/outline.typ": outline_page
#import "../../lib/page.typ": bordered_page, cover_page
#import "../../lib/lib.typ": page_margin

#let report_labels = (
  header: <report_outline_header>,
  page_start: <report_outline_page_start>,
  page_end: <report_outline_page_end>,
)

#let report_page(body, document_code: none) = [
  #bordered_page(
    footer: footer_f2a(document_code: document_code),
  )[
    #body
    #metadata("end") #report_labels.page_end
  ]
]

#let report_outline_page(
  topic: none,
  group: none,
  document_code: [todo],
  implemented_by: [todo],
  reviewed_by: [todo],
  norm_controller: [],
  approved_by: [],
) = {
  outline_page(
    topic: topic,
    group: group,
    document_code: document_code,
    implemented_by: implemented_by,
    reviewed_by: reviewed_by,
    norm_controller: norm_controller,
    approved_by: approved_by,

    start_label: report_labels.page_start,
    end_label: report_labels.page_end,
    header_label: report_labels.header,
  )
}

#let report_abbreviations_page(
  document_code: [todo],
  abbreviations: (
    (
      [todo],
      [todo],
    )
  ),
) = {
  report_page(
    document_code: document_code,
  )[
    #align(center)[
      #heading(numbering: none)[ПЕРЕЛІК СКОРОЧЕНЬ]
    ]

    #table(
      columns: (22mm, 1fr),
      inset: (x: 2mm, y: 1.2mm),
      column-gutter: 8mm,
      align: left + horizon,
      stroke: none,
      ..abbreviations.flatten(),
    )
  ]
}

#let report_title_page(
  topic: none,
  city: none,
  year: none,
) = {
  cover_page(right: page_margin.right)[
    #v(68mm)
    #align(center)[
      #text(
        weight: "bold",
        size: 18pt,
      )[ПОЯСНЮВАЛЬНА ЗАПИСКА\ ДО ДИПЛОМНОГО ПРОЄКТУ]
    ]

    #v(5mm)
    #align(center)[
      на тему: «#underline[#emph(topic)]»
    ]

    #v(1fr)
    #align(center)[#city - #year]
  ]
}
