#import "../../lib/page.typ": bordered_page
#import "../../lib/footer.typ": footer_f2a
#import "../../lib/outline.typ": outline_page

#let technical_task_labels = (
  start_page: <technical_task_start_page>,
  end_page: <technical_task_end_page>,
  header: <technical_task_header>,
)

#let technical_task_outline_heading(level: 1, numbering: none, body) = [#heading(
    level: level,
    numbering: numbering,
  )[#body] #technical_task_labels.header]


#let technical_task_page(body, document_code: none) = [
  #bordered_page(
    footer: footer_f2a(document_code: document_code),
  )[
    #body
    #metadata("end") #technical_task_labels.end_page
  ]
]

#let technical_task_outline_page(
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

    start_label: technical_task_labels.start_page,
    end_label: technical_task_labels.end_page,
    header_label: technical_task_labels.header,
  )
}
