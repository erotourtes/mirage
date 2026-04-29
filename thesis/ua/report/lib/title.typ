#import "../../lib/lib.typ": page_margin
#import "../../lib/page.typ": cover_page

#let report_title_page(
  topic: none,
  city: none,
  year: none,
) = {
  cover_page(right: page_margin.right)[
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
