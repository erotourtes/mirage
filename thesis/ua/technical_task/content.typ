#import "lib/main.typ": (
  technical_task_labels, technical_task_outline_page, technical_task_page,
  technical_task_title_page,
)
#import "../lib/lib.typ": full_document_code

#let technical_task_content(
  body,
  thesis: (:),
) = {
  show heading: it => [
    #it #metadata(it) #technical_task_labels.header
  ]

  technical_task_title_page(
    topic: thesis.topic,
    city: thesis.document.city,
    year: thesis.document.year,
  )

  technical_task_outline_page(
    topic: thesis.topic,
    group: thesis.student.group,
    document_code: full_document_code(thesis.document.codes.technical_task),
    implemented_by: thesis.student.initials,
    reviewed_by: thesis.advisor.initials,
  )

  technical_task_page(document_code: full_document_code(thesis.document.codes.technical_task))[
    #body
  ]
}
