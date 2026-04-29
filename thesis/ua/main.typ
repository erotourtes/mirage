#import "front_matter/title.typ": title_page
#import "technical_task/lib/title.typ": technical_task_title_page
#import "technical_task/lib/content.typ": technical_task_content
#import "technical_task/lib/outline.typ": (
  technical_task_outline_heading, technical_task_outline_page,
)
#import "report/lib/title.typ": report_title_page
#import "report/lib/outline.typ": report_outline_page
#import "report/lib/abbreviations.typ": report_abbreviations_page
#import "front_matter/annotation.typ": annotation_page
#import "front_matter/album_description.typ": album_description_page
#import "front_matter/assignment.typ": assignment_pages

#let document_meta = (
  head_name: [Артем Волокита],
  city: [Київ],
  year: [2026],
)

#let thesis = (
  topic: [Модуль синхронізації текстових даних у розподілених системах],
  student_course: [4],
  student_group: [ІМ-21],
  student_name: [Сірик Максим Олександрович],
  student_sign_name: [Максим СІРИК],
  student_name_initials: [Сірик М. О.],
  student_name_genitive: [Сірика Максима Олександровича],
  advisor_title_line: [ст. наук. співроб., канд. наук, Долголенко О. М.],
  advisor_full_line: [Долголенко Олександр Миколайович],
  advisor_name_initials: [Долголенко О. М.],
  advisor_sign_name: [Олександр ДОЛГОЛЕНКО],
  technical_task_code: [ІАЛЦ.467200.002 ТЗ],
  report_code: [ІАЛЦ.467200.003 ПЗ],
)

#title_page(
  topic: thesis.topic,
  student_course: thesis.student_course,
  student_group: thesis.student_group,
  student_name: thesis.student_name,
  advisor_name: thesis.advisor_title_line,
  head_name: document_meta.head_name,
  city: document_meta.city,
  year: document_meta.year,
)

#assignment_pages(
  topic: thesis.topic,
  student_name: thesis.student_name,
  student_name_genitive: thesis.student_name_genitive,
  advisor_name: thesis.advisor_sign_name,
  advisor_line: thesis.advisor_full_line,
  head_name: document_meta.head_name,
  student_sign_name: thesis.student_sign_name,
  advisor_sign_name: thesis.advisor_sign_name,
  year: document_meta.year,
)

#album_description_page(
  topic: thesis.topic,
  group: thesis.student_group,
)


#technical_task_title_page(
  topic: thesis.topic,
  city: document_meta.city,
  year: document_meta.year,
)

#technical_task_outline_page(
  topic: thesis.topic,
  group: thesis.student_group,
  document_code: thesis.technical_task_code,
  implemented_by: thesis.student_name_initials,
  reviewed_by: thesis.advisor_name_initials,
)

#set heading(numbering: "1")
#show heading.where(level: 1): it => text(
  size: 18pt,
  weight: "bold",
)[
  #if it.numbering != none {
    numbering(it.numbering, ..counter(heading).at(it.location()))
  }
  #it.body
]
#show heading.where(level: 2): it => text(
  size: 16pt,
  weight: "bold",
)[
  #if it.numbering != none {
    numbering(it.numbering, ..counter(heading).at(it.location()))
  }
  #it.body
]
#show heading.where(level: 3): it => text(
  size: 14pt,
  weight: "bold",
)[
  #if it.numbering != none {
    numbering(it.numbering, ..counter(heading).at(it.location()))
  }
  #it.body
]

#technical_task_content(
  document_code: thesis.technical_task_code,
)

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
)
