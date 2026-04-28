#import "../lib/page.typ": outline_page_frame
#import "../lib/footer.typ": footer_f2a
#import "../lib/outline.typ": outline_page

#let report-outline-labels = (
  header: <report-outline-header>,
  page-start: <report-outline-page-start>,
  page-end: <report-outline-page-end>,
)

#let report_outline_heading(level: 1, numbering: none, body) = [
  #heading(
    level: level,
    numbering: numbering,
  )[#body] #report-outline-labels.header
]


#let report_page_frame(body, document-code: none) = [
  #outline_page_frame(
    footer: footer_f2a(
      document-code: document-code,
    ),
  )[
    #body
    #metadata("end") #report-outline-labels.page-end
  ]
]

#let report_outline_page(
  topic: none,
  group: none,
  document-code: [todo],
  implemented-by: [todo],
  reviewed-by: [todo],
  norm-controller: [],
  approved-by: [],
) = {
  outline_page(
    topic: topic,
    group: group,
    document-code: document-code,
    implemented-by: implemented-by,
    reviewed-by: reviewed-by,
    norm-controller: norm-controller,
    approved-by: approved-by,

    end-label: report-outline-labels.page-end,
    start-label: report-outline-labels.page-start,
    header-label: report-outline-labels.header,
  )
}
