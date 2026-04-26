// KPI OT thesis template primitives.
// Coordinates are in PDF points because the official reference PDF was measured
// in points. This keeps page-form alignment direct and auditable.

#let page-width = 210mm
#let page-height = 297mm

// Global KPI OT document offsets.
#let offset-left = 20mm
#let offset-top = 5mm
#let offset-right = 5mm
#let offset-bottom = 5mm

#let font-main = "Times New Roman"

#let title-page-frame(body) = page(
  width: page-width,
  height: page-height,
  margin: 0pt,
  numbering: none,
)[
  #set text(font: font-main, lang: "uk", 14pt)
  #set par(leading: 0pt)
  #body
]

#let at(x, y, body) = place(top + left, dx: x, dy: y, body)

#let text-at(x, y, size: 14pt, weight: "regular", body) = at(x, y)[
  #text(size: size, weight: weight)[#body]
]

#let center-at(y, size: 14pt, weight: "regular", body) = at(0pt, y)[
  #box(width: page-width)[
    #align(center, text(size: size, weight: weight)[#body])
  ]
]

#let rule-at(x, y, width, thickness: 0.55pt) = at(x, y)[
  #line(length: width, stroke: thickness)
]

#let rule-until(x, y, x-end, thickness: 0.55pt) = {
  let width = x-end - x
  rule-at(x, y, width, thickness: thickness)
}

#let note-at(x, y, body) = text-at(x, y, size: 7pt, body)
