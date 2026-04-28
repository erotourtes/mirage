#import "lib/lib.typ": gendered, signature_field, under_field, year_field
#import "lib/page.typ": title_page_frame

#let default-title-meta = (
  university-line: [НАЦІОНАЛЬНИЙ ТЕХНІЧНИЙ УНІВЕРСИТЕТ УКРАЇНИ\ “КИЇВСЬКИЙ ПОЛІТЕХНІЧНИЙ ІНСТИТУТ\ імені ІГОРЯ СІКОРСЬКОГО”],
  faculty: [Факультет інформатики та обчислювальної техніки\ Кафедра обчислювальної техніки],
  project-kind: [Дипломний проєкт],
  degree-line: [на здобуття ступеня бакалавра\ за освітньо-професійною програмою “Інженерія програмного забезпечення\ комп’ютерних систем”\ спеціальності 121 “Інженерія програмного забезпечення”],
)

#let title_page(
  meta: default-title-meta,
  topic: none,
  student-course: none,
  student-group: none,
  student-name: none,
  advisor-name: none,
  consultant-name: none,
  reviewer-name: none,
  head-name: none,
  city: none,
  year: none,
  student-female: false,
) = {
  title_page_frame[
    #block(width: 170mm)[
      #align(center)[
        #text(weight: "bold")[#meta.university-line]
        #v(2mm)
        #underline(meta.faculty)
      ]

      #v(5mm)
      #align(right)[
        #block(width: 90mm)[
          #align(right)[
            #text(weight: "bold")[До захисту допущено:]\
            #text(weight: "bold")[В. о. завідувача кафедри]
          ]
          #grid(
            columns: (20mm, 60mm),
            align: horizon,
            [ #signature_field() ],
            [
              #under_field(start: 20mm)[ #head-name ]
            ],
          )
          #align(right)[
            #year_field()[#year]
          ]
        ]
      ]

      #v(8mm)

      #align(center)[
        #text(weight: "bold", size: 20pt)[#meta.project-kind]\

        #text(weight: "bold")[#meta.degree-line]
      ]

      #v(7mm)

      #stack(
        spacing: 14pt,
        [#text[на тему:] #under_field()[#topic]],
        [
          #gendered([Виконав], [Виконала], is-female: student-female):
          #gendered([студент], [студентка], is-female: student-female)
          #under_field(width: 7mm)[#student-course]
          курсу, групи
          #under_field(width: 20mm, caption: [(шифр групи)])[#student-group]
        ],
        [
          #grid(
            columns: (1fr, 5mm, auto),
            column-gutter: 2mm,
            [#under_field(
              caption: [(прізвище, ім’я, по батькові)],
              width: 100%,
            )[#student-name]],
            [],
            [#signature_field()],
          )
        ],
        [
          #grid(
            columns: (auto, 1fr, 5mm, auto),
            column-gutter: 2mm,
            [Керівник],
            [
              #under_field(
                width: 100%,
                caption: [(посада, науковий ступінь, вчене звання, прізвище та ініціали)],
              )[#advisor-name]
            ],
            [],
            [#signature_field()],
          )
        ],
        [
          #grid(
            columns: (auto, auto, 1fr, 5mm, auto),
            column-gutter: 2mm,
            [Концультант],
            [#under_field(caption: [(назва розділу)])[(нормконтроль)]],
            [
              #under_field(
                width: 100%,
                caption: [(посада, вчене звання, науковий ступінь, прізвище та ініціали)],
                caption-width: 220pt,
                caption-dx: -15pt,
              )[#consultant-name]
            ],
            [],
            [#signature_field()],
          )
        ],
        [
          #grid(
            columns: (auto, 1fr, 5mm, auto),
            column-gutter: 2mm,
            [Рецензент],
            [
              #under_field(
                caption: [(посада, науковий ступінь, вчене звання, прізвище та ініціали)],
                width: 100%,
              )[#reviewer-name]
            ],
            [],
            [#signature_field()],
          )
        ],
      )

      #v(5mm)
      #align(right)[
        #block(width: 85mm)[
          #align(left)[
            Засвідчую, що у цьому дипломному проєкті
            немає запозичень з праць інших авторів без
            відповідних посилань.
            #grid(
              columns: (auto, 28mm),
              column-gutter: 7mm,
              align: horizon,
              [#gendered([Студент], [Студентка], is-female: student-female)],
              [#signature_field()],
            )
          ]
        ]
      ]

      #v(1fr)
      #align(center)[#city – #year р.]
    ]
  ]
}
