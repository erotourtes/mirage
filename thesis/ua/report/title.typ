#import "../lib/lib.typ": offset-right
#import "../lib/page.typ": title_page_frame

#let report_title_page(
  topic: none,
  city: none,
  year: none,
) = {
  title_page_frame(right: offset-right)[
    #v(68mm)
    #align(center)[
      #text(
        weight: "bold",
        size: 18pt,
      )[ПОЯСНЮВАЛЬНА ЗАПИСКА\ ДО ДИПЛОМНОГО ПРОЄКТУ]
    ]

    #v(5mm)
    #align(center)[
      на тему: «#underline[#emph(topic)]»
    ]

    #v(1fr)
    #align(center)[#city - #year]
  ]
}
