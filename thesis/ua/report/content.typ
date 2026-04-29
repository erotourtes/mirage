#import "lib/main.typ": (
  report_abbreviations_page, report_labels, report_outline_page,
  report_page, report_title_page,
)


#let report_content(thesis: (:), document_meta: (:), body) = [
  #show heading: it => [
    #it #metadata(it) #report_labels.header
  ]

  #report_title_page(
    topic: thesis.topic,
    city: document_meta.city,
    year: document_meta.year,
  )

  #report_outline_page(
    topic: thesis.topic,
    group: thesis.student_group,
    document_code: thesis.report_code,
    implemented_by: thesis.student_name_initials,
    reviewed_by: thesis.advisor_name_initials,
  )

  #report_abbreviations_page(
    document_code: thesis.report_code,
    abbreviations: thesis.abbreviations,
  )

  #report_page[
    #body
  ]
]
