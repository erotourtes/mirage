#import "lib/template.typ": thesis_template
#import "technical_task/content.typ": technical_task_content
#import "report/content.typ": report_content, report_section_heading

#let thesis = (
  topic: [Модуль синхронізації текстових даних у розподілених системах],
  document: (
    head_name: [Артем Волокита],
    city: [Київ],
    year: [2026],
    codes: (
      technical_task: (
        number: [ІАЛЦ.467200.002],
        short_form: [ТЗ],
        long_form: [Технічне завдання],
      ),
      report: (
        number: [ІАЛЦ.467200.003],
        short_form: [ПЗ],
        long_form: [Пояснювальна записка],
      ),
      d1: (
        number: [ІАЛЦ.467200.004],
        short_form: [Д1],
        long_form: [Структурна схема],
      ),
      d2: (
        number: [ІАЛЦ.467200.005],
        short_form: [Д2],
        long_form: [Функціональна схема],
      ),
      d3: (
        number: [ІАЛЦ.467200.006],
        short_form: [Д3],
        long_form: [Принципова схема],
      ),
      d4: (
        number: [ІАЛЦ.467200.007],
        short_form: [Д4],
        long_form: [Текст програмного коду],
      ),
    ),
  ),
  student: (
    course: [4],
    group: [ІМ-21],
    full_name: [Сірик Максим Олександрович],
    sign_name: [Максим СІРИК],
    initials: [Сірик М. О.],
    genitive_name: [Сірика Максима Олександровича],
  ),
  advisor: (
    title_line: [ст. наук. співроб., канд. наук, Долголенко О. М.],
    full_name: [Долголенко Олександр Миколайович],
    sign_name: [Олександр ДОЛГОЛЕНКО],
    initials: [Долголенко О. М.],
  ),
  report: (
    abbreviations: (
      ([todo], [todo])
    ),
  ),
)

#show: doc => thesis_template(
  thesis: thesis,
  doc,
)

#technical_task_content(
  thesis: thesis,
)[
  = todo \
  == todo naother
]

#report_content(
  thesis: thesis,
)[
  #report_section_heading[todo]
]
