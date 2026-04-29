#import "../../lib/footer.typ": footer_f2, footer_f2a
#import "../../lib/lib.typ": full_document_code, page_margin
#import "../../lib/page.typ": bordered_page, cover_page

#let appendix_sheet_count(meta) = context {
  let starts = query(meta.start_label)
  let ends = query(meta.end_label)

  if starts.len() == 0 or ends.len() == 0 {
    [??]
  } else {
    let start_page = starts.first().location().page()
    let end_page = ends.last().location().page()
    end_page - start_page + 1
  }
}

#let appendix_title_page(
  number: none,
  topic: none,
  code: (:),
  city: none,
  year: none,
  sheet_count: none,
) = {
  let sheets = if sheet_count == none {
    [todo]
  } else {
    sheet_count
  }

  cover_page(right: page_margin.right)[
    #align(center)[
      #v(30mm)
      #text(size: 18pt, weight: "bold")[ДОДАТОК #number]

      #v(10mm)
      #text(size: 18pt)[#topic]

      #v(40mm)
      #text(size: 18pt)[#code.long_form]
      #v(3mm)
      #text(size: 18pt)[#full_document_code(code)]

      #v(53mm)
      #text(size: 16pt)[Аркушів #sheets]

      #v(1fr)
      #text(size: 14pt, weight: "bold")[#city #year р]
    ]
  ]
}

#let appendix_page(
  meta,
  body,
  topic: none,
  group: none,
  code: (:),
  implemented_by: [todo],
  reviewed_by: [todo],
  norm_controller: [],
  approved_by: [],
) = context {
  counter(page).update(1)

  let document_code = full_document_code(code)
  let first_footer = footer_f2(
    code.long_form,
    topic: topic,
    group: group,
    document_code: document_code,
    sheet_number: [1],
    sheet_count: appendix_sheet_count(meta),
    implemented_by: implemented_by,
    reviewed_by: reviewed_by,
    norm_controller: norm_controller,
    approved_by: approved_by,
  )

  bordered_page(
    footer_space: measure(first_footer).height,
    footer: context {
      let page_number = counter(page).get().first()
      if page_number == 1 {
        first_footer
      } else {
        footer_f2a(document_code: document_code)
      }
    },
  )[
    #metadata("start") #meta.start_label
    #body
    #metadata("end") #meta.end_label
  ]
}
