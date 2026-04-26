#import "title.typ": title-page
#import "assignment.typ": assignment-pages

#let thesis = (
  topic: [Модуль синхронізації текстових даних у розподілених системах],
  student-course: [4],
  student-group: [ІМ-21],
  student-name: [Сірик Максим Олександрович],
  student-sign-name: [Максим СІРИК],
  student-name-genitive: [Сірика Максима Олександровича],
  advisor-title-line: [ст. наук. співроб., канд. наук, Долголенко О. М.],
  advisor-full-line: [Долголенко Олександр Миколайович],
  advisor-sign-name: [Олександр ДОЛГОЛЕНКО],
)

#title-page(
  topic: thesis.topic,
  student-course: thesis.student-course,
  student-group: thesis.student-group,
  student-name: thesis.student-name,
  advisor-name: thesis.advisor-title-line,
)

#assignment-pages(
  topic: thesis.topic,
  student-name: thesis.student-name,
  student-name-genitive: thesis.student-name-genitive,
  advisor-name: thesis.advisor-sign-name,
  advisor-line: thesis.advisor-full-line,
  student-sign-name: thesis.student-sign-name,
  advisor-sign-name: thesis.advisor-sign-name,
)

= section 1
= section 2
= section 3
= section 4
