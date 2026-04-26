#import "../lib.typ": title_page_frame, offset-right

#let technical-task-title-page(
  topic: none,
  city: none,
  year: none,
) = {
  title_page_frame(right: offset-right)[
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
