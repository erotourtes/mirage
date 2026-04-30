#import "lib/index.typ": (
  report_abbreviations_page, report_labels, report_outline_page, report_page,
  report_section_counter, report_section_heading, report_title_page,
)
#import "../lib/lib.typ": full_document_code


#let report_content(thesis: none, body) = [
  #report_section_counter.update(0)
  #show heading: it => [
    #it #metadata(it) #report_labels.header
  ]

  #report_title_page(
    topic: thesis.topic,
    city: thesis.document.city,
    year: thesis.document.year,
  )

  #report_outline_page(
    document_name: thesis.document.codes.report.long_form,
    topic: thesis.topic,
    group: thesis.student.group,
    document_code: full_document_code(code: thesis.document.codes.report),
    implemented_by: thesis.student.initials,
    reviewed_by: thesis.advisor.initials,
    norm_controller: thesis.document.norm_controller,
    approved_by: thesis.document.approved_by,
  )

  #report_abbreviations_page(
    document_code: full_document_code(code: thesis.document.codes.report),
    abbreviations: thesis.report.abbreviations,
  )

  #report_page(document_code: full_document_code(code: thesis.document.codes.report))[
    #body
  ]
]
