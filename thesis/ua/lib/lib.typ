// KPI OT thesis template primitives.

#let page-width = 210mm
#let page-height = 297mm

// Global KPI OT document offsets.
#let offset-left = 20mm
#let offset-top = 5mm
#let offset-right = 5mm
#let offset-bottom = 5mm

#let font-main = "Times New Roman"


#let gendered(male, female, is-female: false) = {
  if is-female {
    female
  } else {
    male
  }
}

#let under_field(
  body,
  width: auto,
  start: 0pt,
  end: 0pt,
  caption: none,
  caption-size: 8pt,
  caption-dy: 2pt,
  caption-dx: 0pt,
  caption-width: none,
  caption-align: center,
  body-align: center,
  stroke: 0.55pt,
  value-size: 14pt,
  line-gap: 0pt,
  baseline-ratio: 0.34,
) = context {
  let body-width = measure(body).width
  let w = if width == auto {
    body-width + start + end
  } else {
    width
  }

  let text-baseline = value-size * baseline-ratio

  box(width: w, height: value-size + line-gap, baseline: text-baseline)[
    #h(start)
    #box(width: w - start - end)[
      #align(body-align)[
        #text(size: value-size)[#body]
      ]
    ]

    #place(bottom + left)[
      #line(length: w, stroke: stroke)
    ]

    #if caption != none {
      let cw = if caption-width == none { w } else { caption-width }

      place(top + left, dx: caption-dx, dy: value-size + line-gap + caption-dy)[
        #box(width: cw)[
          #align(caption-align)[
            #text(size: caption-size)[#caption]
          ]
        ]
      ]
    }
  ]
}

#let signature_width = 30mm

#let signature_field(
  start: 0pt,
  end: 0pt,
  width: signature_width,
) = [
  #under_field(
    width: width,
    start: start,
    end: end,
    caption: [(підпис)],
  )[]
]

#let year_field(body) = [
  “#under_field(end: 7mm)[]” #under_field(end: 20mm)[] #body р.
]
