#import "lib.typ": body_par_indent, body_par_leading, body_text_size, font_main

#let bibliography_title = [Список використаних джерел]
#let bibliography_style = "gost-r-705-2008-numeric"

#let document_text_rules(body) = {
  set text(font: font_main, body_text_size)
  set par(
    justify: true,
    leading: body_par_leading,
    first-line-indent: (
      amount: body_par_indent,
      all: true,
    ),
  )
  set list(spacing: 0pt)
  set enum(spacing: 0pt)
  body
}

#let figure_caption_rules(body) = {
  set figure.caption(separator: [ --- ])

  show figure.where(kind: image): set figure(
    supplement: [Рисунок],
    gap: 14pt,
  )

  show figure.where(kind: table): set figure(
    supplement: [Таблиця],
  )
  show figure.where(kind: table): set figure.caption(position: top)
  show figure.caption.where(kind: table): it => align(left)[
    #box(
      inset: (left: body_par_leading - 8pt),
    )[
      #it
    ]
  ]
  body
}

#let document_theme_rules(body) = {
  figure_caption_rules(document_text_rules(body))
}

#let bibliography_section(
  sources,
  title: bibliography_title,
  style: bibliography_style,
  full: false,
) = [
  #heading(numbering: none)[#title]
  #bibliography(
    sources,
    title: none,
    style: style,
    full: full,
  )
]
