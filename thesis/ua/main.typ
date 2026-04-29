#import "lib/template.typ": thesis_template
#import "technical_task/content.typ": technical_task_content
#import "report/content.typ": report_content

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
  abbreviations: (
    ([todo], [todo])
  ),
)

#show: doc => thesis_template(
  document_meta: document_meta,
  thesis: thesis,
  doc,
)

#technical_task_content(
  thesis: thesis,
  document_meta: document_meta,
)[
  = todo
]

#report_content(
  thesis: thesis,
  document_meta: document_meta,
)[
  = todo
]
