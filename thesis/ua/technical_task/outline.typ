#import "../lib/page.typ": outline_page_frame
#import "../lib/footer.typ": footer_f2, footer_f2a
#import "../lib/outline.typ": outline_page

#let technical-task-labels = (
  start-page: <technical-task-start-page>,
  end-page: <technical-task-end-page>,
  header: <technical-task-header>,
)

#let technical_task_outline_heading(level: 1, body) = [#heading(
    level: 1,
  )[#body] #technical-task-labels.header]


#let technical_task_page_frame(body) = [
  #outline_page_frame(
    footer: footer_f2a(),
  )[
    #body
    #metadata("end") #technical-task-labels.end-page
  ]
]

#let technical_task_outline_page(
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

    start-label: technical-task-labels.start-page,
    end-label: technical-task-labels.end-page,
    header-label: technical-task-labels.header,
  )
}
