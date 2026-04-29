// KPI OT thesis template primitives.

#let page_size = (
  width: 210mm,
  height: 297mm,
)

// Global KPI OT document offsets.
#let page_margin = (
  left: 20mm,
  top: 5mm,
  right: 5mm,
  bottom: 5mm,
)

#let font_main = "Times New Roman"

#let full_document_code(code) = [#code.number #code.short_form]


#let gendered(male, female, is_female: false) = {
  if is_female {
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
  caption_size: 8pt,
  caption_dy: 2pt,
  caption_dx: 0pt,
  caption_width: none,
  caption_align: center,
  body_align: center,
  stroke: 0.55pt,
  value_size: 14pt,
  line_gap: 0pt,
  baseline_ratio: 0.34,
) = context {
  let body_width = measure(body).width
  let w = if width == auto {
    body_width + start + end
  } else {
    width
  }

  let text_baseline = value_size * baseline_ratio

  box(width: w, height: value_size + line_gap, baseline: text_baseline)[
    #h(start)
    #box(width: w - start - end)[
      #align(body_align)[
        #text(size: value_size)[#body]
      ]
    ]

    #place(bottom + left)[
      #line(length: w, stroke: stroke)
    ]

    #if caption != none {
      let caption_box_width = if caption_width == none { w } else { caption_width }

      place(top + left, dx: caption_dx, dy: value_size + line_gap + caption_dy)[
        #box(width: caption_box_width)[
          #align(caption_align)[
            #text(size: caption_size)[#caption]
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
