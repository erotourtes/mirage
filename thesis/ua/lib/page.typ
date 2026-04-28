#import "lib.typ": (
  font-main, offset-bottom, offset-left, offset-right, offset-top, page-height,
  page-width,
)

#let title_page_frame(body, right: none) = page(
  width: page-width,
  height: page-height,
  margin: (
    left: offset-left,
    right: if right == none { offset-left } else { right },
    top: offset-left,
    bottom: offset-left,
  ),
  numbering: none,
)[
  #set text(font: font-main, lang: "ua", 14pt)
  #body
]

#let standard_page_frame(body, background: none, footer: none) = context {
  page(
    width: page-width,
    height: page-height,
    margin: (
      left: offset-left,
      right: offset-right,
      top: offset-top,
      bottom: offset-bottom + measure(footer).height,
    ),
    background: background,
    footer: footer,
    footer-descent: 0mm,
    numbering: none,
  )[
    #set text(font: font-main, lang: "ua", 14pt)
    #set par(justify: true, leading: 0.62em)
    #body
  ]
}

#let outline_page_frame(body, footer: none) = {
  standard_page_frame(
    background: place(
      top + left,
      dx: offset-left,
      dy: offset-top,
    )[
      #box(
        width: page-width - offset-left - offset-right,
        height: page-height - offset-top - offset-bottom,
        stroke: 2pt,
      )
    ],
    footer: footer,
  )[
    #pad(x: 12mm, top: 12mm, bottom: 8mm)[
      #body
    ]
  ]
}
