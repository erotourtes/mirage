#import "title.typ": title_page
#import "technical_task/title.typ": technical-task-title-page
#import "technical_task/content.typ": technical_task_content
#import "technical_task/outline.typ": (
  technical_task_outline_heading, technical_task_outline_page,
)
#import "annotation.typ": annotation-page
#import "album_description.typ": album_description_page
#import "assignment.typ": assignment_pages

#let document-meta = (
  head-name: [Артем Волокита],
  city: [Київ],
  year: [2026],
)

#let thesis = (
  topic: [Модуль синхронізації текстових даних у розподілених системах],
  student-course: [4],
  student-group: [ІМ-21],
  student-name: [Сірик Максим Олександрович],
  student-sign-name: [Максим СІРИК],
  student-name-initials: [Сірик М. О.],
  student-name-genitive: [Сірика Максима Олександровича],
  advisor-title-line: [ст. наук. співроб., канд. наук, Долголенко О. М.],
  advisor-full-line: [Долголенко Олександр Миколайович],
  advisor-name-initials: [Долголенко О. М.],
  advisor-sign-name: [Олександр ДОЛГОЛЕНКО],
  technical-task-code: [ІАЛЦ.467200.002 ТЗ],
)

#title_page(
  topic: thesis.topic,
  student-course: thesis.student-course,
  student-group: thesis.student-group,
  student-name: thesis.student-name,
  advisor-name: thesis.advisor-title-line,
  head-name: document-meta.head-name,
  city: document-meta.city,
  year: document-meta.year,
)

#assignment_pages(
  topic: thesis.topic,
  student-name: thesis.student-name,
  student-name-genitive: thesis.student-name-genitive,
  advisor-name: thesis.advisor-sign-name,
  advisor-line: thesis.advisor-full-line,
  head-name: document-meta.head-name,
  student-sign-name: thesis.student-sign-name,
  advisor-sign-name: thesis.advisor-sign-name,
  year: document-meta.year,
)

#album_description_page(
  topic: thesis.topic,
  group: thesis.student-group,
)


#technical-task-title-page(
  topic: thesis.topic,
  city: document-meta.city,
  year: document-meta.year,
)

#technical_task_outline_page(
  topic: thesis.topic,
  group: thesis.student-group,
  document-code: thesis.technical-task-code,
  implemented-by: thesis.student-name-initials,
  reviewed-by: thesis.advisor-name-initials,
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
  document-code: thesis.technical-task-code,
)
