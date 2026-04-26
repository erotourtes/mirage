#import "lib.typ": title-page-frame, page-width, page-height, at, text-at, note-at, rule-at, rule-until, offset-left

#let default-title-meta = (
  university-line-1: [НАЦІОНАЛЬНИЙ ТЕХНІЧНИЙ УНІВЕРСИТЕТ УКРАЇНИ],
  university-line-2: [“КИЇВСЬКИЙ ПОЛІТЕХНІЧНИЙ ІНСТИТУТ],
  university-line-3: [імені ІГОРЯ СІКОРСЬКОГО”],
  faculty: [Факультет інформатики та обчислювальної техніки],
  department: [Кафедра обчислювальної техніки],
  head-name: [Артем Волокита],
  project-kind: [Дипломний проєкт],
  degree-line: [на здобуття ступеня бакалавра],
  program-line-1: [за освітньо-професійною програмою “Інженерія програмного забезпечення],
  program-line-2: [комп’ютерних систем”],
  specialty-line: [спеціальності 121 “Інженерія програмного забезпечення”],
  city: [Київ],
  year: [2026],
)

#let filled-field-at(x, y, width, size: 14pt, body) = {
  if body != none {
    at(x, y)[
      #box(width: width)[
        #align(center, text(size: size)[#body])
      ]
    ]
  }
}

#let title-offset-left = offset-left
#let title-offset-top = 65.43pt
#let title-offset-right = page-width - title-offset-left 
#let title-offset-bottom = page-height - 813.64pt
#let title-center-shift = 6.8pt

#let title-center-at(y, size: 14pt, weight: "regular", body) = at(title-center-shift, y)[
  #box(width: page-width)[
    #align(center, text(size: size, weight: weight)[#body])
  ]
]

#let signature-x = 428pt
#let signature-width = 66pt
#let signature-end-x = signature-x + signature-width
#let field-line-end-x = signature-x - 7pt

#let title-page(
  meta: default-title-meta,
  topic: none,
  student-course: none,
  student-group: none,
  student-name: none,
  advisor-name: none,
) = {
  title-page-frame[
    // University block.
    #title-center-at(title-offset-top, weight: "bold", meta.university-line-1)
    #title-center-at(81.53pt, weight: "bold", meta.university-line-2)
    #title-center-at(97.63pt, weight: "bold", meta.university-line-3)

    #title-center-at(122.93pt, meta.faculty)
    #rule-at(150.6pt, 137.1pt, 308.4pt)
    #title-center-at(148.23pt, meta.department)
    #rule-at(204.8pt, 162.4pt, 199.9pt)

    // Admission block.
    #text-at(410.8pt, 180.43pt, weight: "bold")[До захисту допущено:]
    #text-at(394pt, 196.53pt, weight: "bold")[В. о. завідувача кафедри]
    #text-at(443pt, 212.63pt, meta.head-name)
    #rule-at(437pt, 227pt, 111.6pt)
    #rule-at(355pt, 226.9pt, 64.5pt)
    #note-at(375.4pt, 228.42pt)[(підпис)]
    #text-at(410.8pt, 243.62pt)[“]
    #rule-at(416pt, 255.2pt, 13.6pt)
    #text-at(429.55pt, 243.62pt)[”]
    #rule-at(439pt, 255.2pt, 61pt)
    #text-at(500.3pt, 243.62pt)[#meta.year р.]

    // Main title block.
    #title-center-at(268.08pt, size: 20pt, weight: "bold", meta.project-kind)
    #title-center-at(296.83pt, weight: "bold", meta.degree-line)
    #title-center-at(318.93pt, weight: "bold", meta.program-line-1)
    #title-center-at(343.08pt, weight: "bold", meta.program-line-2)
    #title-center-at(367.23pt, weight: "bold", meta.specialty-line)

    // Topic and author.
    #text-at(title-offset-left, 411.18pt)[на тему:]
    #rule-until(109pt, 424.5pt, signature-end-x)
    #filled-field-at(112pt, 410.6pt, 400pt, size: 12pt, topic)

    #text-at(title-offset-left, 439.28pt)[Виконав (-ла): студент (-ка)]
    #rule-at(226pt, 452.6pt, 24pt)
    #filled-field-at(226pt, 439.28pt, 24pt, student-course)
    #text-at(254.1pt, 439.28pt)[курсу, групи]
    #rule-at(333pt, 452.6pt, 60pt)
    #filled-field-at(333pt, 439.28pt, 60pt, student-group)
    #note-at(340pt, 455.01pt)[(шифр групи)]

    #rule-until(title-offset-left, 482.85pt, field-line-end-x)
    #filled-field-at(title-offset-left, 468.8pt, 361pt, student-name)
    #note-at(191.5pt, 485.16pt)[(прізвище, ім’я, по батькові)]
    #rule-at(signature-x, 482.85pt, signature-width)
    #note-at(453.7pt, 485.16pt)[(підпис)]

    // Supervisors and reviewers.
    #text-at(title-offset-left, 505.33pt)[Керівник]
    #rule-until(115pt, 518.7pt, field-line-end-x)
    #filled-field-at(
      115pt,
      505.7pt,
      301.5pt,
      advisor-name,
    )
    #note-at(148.95pt, 521.06pt)[(посада, науковий ступінь, вчене звання, прізвище та ініціали)]
    #rule-at(signature-x, 518.7pt, signature-width)
    #note-at(453.7pt, 521.06pt)[(підпис)]

    #rule-until(135pt, 554.6pt, 242pt - 7pt)
    #text-at(title-offset-left, 541.23pt)[Консультант (нормоконтроль)]
    #rule-until(242pt, 554.6pt, field-line-end-x)
    #note-at(145.7pt, 556.96pt)[(назва розділу)]
    #note-at(240pt, 556.96pt)[(посада, вчене звання, науковий ступінь, прізвище та ініціали)]
    #rule-at(signature-x, 554.6pt, signature-width)
    #note-at(453.7pt, 556.96pt)[(підпис)]

    #text-at(title-offset-left, 577.13pt)[Рецензент]
    #rule-until(121pt, 590.5pt, field-line-end-x)
    #note-at(145pt, 592.86pt)[(посада, науковий ступінь, вчене звання, прізвище та ініціали)]
    #rule-at(signature-x, 590.5pt, signature-width)
    #note-at(453.7pt, 592.86pt)[(підпис)]

    // Originality statement.
    #text-at(283.6pt, 607.03pt)[Засвідчую, що у цьому дипломному проєкті]
    #text-at(283.6pt, 623.13pt)[немає запозичень з праць інших авторів без]
    #text-at(283.6pt, 639.23pt)[відповідних посилань.]
    #text-at(283.6pt, 655.33pt)[Студент (-ка)]
    #rule-at(367pt, 668pt, 78pt)
    #text-at(390.4pt, 671.08pt, size: 6pt)[(підпис)]

    #title-center-at(699.08pt)[#meta.city – #meta.year р.]
  ]
}
