#import "../../lib/page.typ": bordered_page
#import "../../lib/footer.typ": footer_f2a
#import "../../lib/outline.typ": outline_page

#let report_outline_labels = (
  header: <report_outline_header>,
  page_start: <report_outline_page_start>,
  page_end: <report_outline_page_end>,
)

#let report_outline_heading(level: 1, numbering: none, body) = [
  #heading(
    level: level,
    numbering: numbering,
  )[#body] #report_outline_labels.header
]


#let report_page(body, document_code: none) = [
  #bordered_page(
    footer: footer_f2a(
      document_code: document_code,
    ),
  )[
    #body
    #metadata("end") #report_outline_labels.page_end
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

    end_label: report_outline_labels.page_end,
    start_label: report_outline_labels.page_start,
    header_label: report_outline_labels.header,
  )
}
