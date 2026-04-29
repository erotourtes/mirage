#import "lib/main.typ": (
  technical_task_labels, technical_task_outline_page, technical_task_page,
  technical_task_title_page,
)

#let technical_task_content(
  body,
  thesis: (:),
  document_meta: (:),
) = {
  show heading: it => [
    #it #metadata(it) #technical_task_labels.header
  ]

  technical_task_title_page(
    topic: thesis.topic,
    city: document_meta.city,
    year: document_meta.year,
  )

  technical_task_outline_page(
    topic: thesis.topic,
    group: thesis.student_group,
    document_code: thesis.technical_task_code,
    implemented_by: thesis.student_name_initials,
    reviewed_by: thesis.advisor_name_initials,
  )

  technical_task_page(document_code: thesis.technical_task_code)[
    #body
  ]
}
