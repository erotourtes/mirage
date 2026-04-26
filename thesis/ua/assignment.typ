#import "lib.typ": signature_field, title_page_frame, under_field, year_field

#let task-list(start: 1, body) = {
  set enum(
    numbering: "1.",
    start: start,
    body-indent: 5mm,
  )
  body
}

#let task-line(body) = enum.item(body)

#let task-row(number, body) = grid(
  columns: (9mm, 1fr),
  column-gutter: 3mm,
  align: top,
  [#number.], body,
)

#let default-assignment-meta = (
  university-line: [НАЦІОНАЛЬНИЙ ТЕХНІЧНИЙ УНІВЕРСИТЕТ УКРАЇНИ\ "КИЇВСЬКИЙ ПОЛІТЕХНІЧНИЙ ІНСТИТУТ\ імені ІГОРЯ СІКОРСЬКОГО"],
  faculty: [Факультет інформатики та обчислювальної техніки\ Кафедра обчислювальної техніки],
  education-level: [Рівень вищої освіти - перший (бакалавр)\ Освітньо-професійна програма\ "Інженерія програмного забезпечення комп’ютерних систем"\ спеціальності 121 “Інженерія програмного забезпечення”],
  head-name: [Артем Волокита],
  year: [2026],
)

#let assignment-pages(
  meta: default-assignment-meta,
  topic: none,
  student-name: none,
  student-name-genitive: none,
  advisor-name: none,
  advisor-line: none,
  order-line: [todo],
  due-date: [todo],
  input-data: [технічна документація, теоретичні дані.],
  graphics: [todo],
  norm-controller: [],
  issue-date: [todo],
  calendar: (
    ([Затвердження теми проекту], [], []),
    ([Вивчення та аналіз завдання], [], []),
    (
      [Розробка архітектури та загальної структури системи],
      [],
      [],
    ),
    ([Розробка структур окремих підсистем], [], []),
    ([Програмна реалізація системи], [], []),
    ([Оформлення пояснювальної записки], [], []),
    ([Захист програмного продукту], [], []),
    ([Передзахист], [], []),
    ([Захист], [], []),
  ),
  student-sign-name: none,
  advisor-sign-name: none,
) = {
  title_page_frame[
    #v(18mm)
    #align(center)[
      #align(center)[
        #text(weight: "bold")[#meta.university-line]
        #v(2mm)
        #underline[#meta.faculty]
      ]
      #v(1mm)
      #stack(
        spacing: 10pt,
        [#meta.education-level],
      )
    ]

    #v(6mm)
    #align(right)[
      #block(width: 90mm)[
        #align(right)[
          #text(weight: "bold")[ЗАТВЕРДЖУЮ]\
          #text(weight: "bold")[В. о. завідувача кафедри]
        ]
        #grid(
          columns: (20mm, 60mm),
          align: horizon,
          [ #signature_field() ],
          [
            #under_field(start: 20mm)[ #meta.head-name ]
          ],
        )
        #align(right)[
          #year_field()[#meta.year]
        ]
      ]
    ]

    #v(3mm)
    #align(center)[
      #text(weight: "bold")[ЗАВДАННЯ]\
      на бакалаврський дипломний проект студента\
      #v(3mm)
      #underline[#student-name-genitive]
    ]

    #v(7mm)
    #task-list[
      #task-line[
        Тема проекту #underline[#emph(topic)]\
        керівник проекту
        #under_field(caption: [(прізвище, ім'я, по батькові, науковий ступінь, вчене звання)])[ #advisor-line ],\
        затверджені наказом по університету від #underline[#order-line]
      ]

      #task-line[
        Термін здачі студентом закінченого проекту #underline[#due-date]
      ]

      #task-line[
        Вихідні дані до проекту #underline[#emph(input-data)]
      ]

      #task-line[
        Зміст розрахунково-пояснювальної записки (перелік питань, які розробляються)\
        #context for section in {
          query(heading.where(level: 1)).map(heading => heading.body)
        } [
          #h(8mm)#underline[#section]\
        ]
      ]
    ]
  ]

  title_page_frame[
    #task-list(start: 5)[
      #task-line[
        Перелік графічного матеріалу (з точним позначенням обов'язкових креслень)
        #underline[#graphics]
      ]

      #task-line[
        Консультанта проекту, з вказівкою розділів проекту, які до них вносяться
      ]
    ]

    #v(2mm)
    #box(width: 171mm)[
      #table(
        columns: (37mm, 1fr, 34mm, 34mm),
        rows: (auto, auto, 9mm, 9mm),
        stroke: 0.6pt,
        inset: 2pt,
        align: horizon + center,
        table.cell(rowspan: 2)[Розділ],
        table.cell(rowspan: 2)[Консультант],
        table.cell(colspan: 2)[Підпис, дата],
        [Завдання\ видав],
        [Завдання\ прийняв],
        [Нормоконтроль],
        [#norm-controller],
        [],
        [],
        [],
        [],
        [],
        [],
      )
    ]

    #v(8mm)
    #task-list(start: 7)[
      #task-line[
        Дата видачі завдання «#underline[#issue-date].»
      ]
    ]

    #v(5mm)
    #align(center)[Календарний план]
    #box(width: 172mm)[
      #table(
        columns: (10mm, 77mm, 55mm, 1fr),
        stroke: 0.6pt,
        inset: (x: 2pt, y: 3pt),
        align: horizon + left,
        [№\ п/п],
        [Найменування етапів\ дипломного проекту],
        [Терміни виконання\ етапів проекту],
        [Примітки],
        ..calendar
          .enumerate()
          .map(((index, row)) => (
            [#calc.round(index + 1).],
            [#emph(row.at(0))],
            [#row.at(1)],
            [#row.at(2)],
          ))
          .flatten(),
      )
    ]

    #v(10mm)
    #grid(
      columns: (auto, auto, 5mm, 1fr),
      column-gutter: 2mm,
      row-gutter: 7mm,
      align: horizon,
      [Студент-дипломник],
      [#signature_field()],
      [],
      [#under_field(
        width: 100%,
        body-align: right,
      )[
        #student-sign-name
      ]],

      [Керівник проекту],
      [#signature_field()],
      [],
      [#under_field(width: 100%, body-align: right)[
        #advisor-sign-name
      ]],
    )
  ]
}
