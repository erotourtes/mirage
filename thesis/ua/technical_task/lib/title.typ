#import "../../lib/lib.typ": page_margin
#import "../../lib/page.typ": cover_page

#let technical_task_title_page(
  topic: none,
  city: none,
  year: none,
) = {
  cover_page(right: page_margin.right)[
    #set par(justify: false)

    #v(68mm)
    #align(center)[
      #text(
        weight: "bold",
        size: 18pt,
      )[ТЕХНІЧНЕ ЗАВДАННЯ\ ДО ДИПЛОМНОГО ПРОЄКТУ]
    ]

    #v(5mm)
    #align(center)[
      на тему: «#underline[#emph(topic)]»
    ]

    #v(1fr)
    #align(center)[#city - #year]
  ]
}
