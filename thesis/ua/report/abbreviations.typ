#import "outline.typ": report_outline_heading, report_page_frame

#let report-abbreviations-page(
  document-code: [todo],
  abbreviations: (
    (
      [todo],
      [todo],
    )
  ),
) = {
  report_page_frame(
    document-code: document-code,
  )[
    #align(center)[
      #report_outline_heading(numbering: none)[ПЕРЕЛІК СКОРОЧЕНЬ]
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
