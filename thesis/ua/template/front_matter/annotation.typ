#import "../lib/page.typ": cover_page

#let annotation_page(
  text_ua: none,
  text_en: none,
) = {
  cover_page[
    #align(center)[
      #text(weight: "bold")[АНОТАЦІЯ]
    ]
    #par(justify: true)[#text_ua]

    #v(6mm)
    #align(center)[
      #text(weight: "bold")[ANNOTATION]
    ]
    #par(justify: true)[#text_en]
  ]
}
