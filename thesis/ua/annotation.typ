#import "lib/page.typ": title_page_frame

#let annotation-page(
  text-ua: [todo],
  text-en: [todo],
) = {
  title_page_frame[
    #align(center)[
      #text(weight: "bold")[АНОТАЦІЯ]
    ]
    #par(justify: true)[#text-ua]

    #v(6mm)
    #align(center)[
      #text(weight: "bold")[ANNOTATION]
    ]
    #par(justify: true)[#text-en]
  ]
}
