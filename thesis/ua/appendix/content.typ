#import "lib/index.typ": (
  appendix_page, appendix_title_page,
)
#import "../lib/lib.typ": page_range_sheet_count

#let appendix_content(meta, thesis: (:), body) = {
  let code = thesis.document.codes.at(meta.code_key)

  [
    #appendix_title_page(
      number: meta.number,
      topic: thesis.topic,
      code: code,
      city: thesis.document.city,
      year: thesis.document.year,
      sheet_count: page_range_sheet_count(meta.start_label, meta.end_label),
    )

    #appendix_page(
      meta,
      topic: thesis.topic,
      group: thesis.student.group,
      code: code,
      implemented_by: thesis.student.initials,
      reviewed_by: thesis.advisor.initials,
    )[#body]
  ]
}

#let appendix_d1_meta = (
  number: [1],
  code_key: "d1",
  start_label: <appendix_d1_start>,
  end_label: <appendix_d1_end>,
)

#let appendix_d2_meta = (
  number: [2],
  code_key: "d2",
  start_label: <appendix_d2_start>,
  end_label: <appendix_d2_end>,
)

#let appendix_d3_meta = (
  number: [3],
  code_key: "d3",
  start_label: <appendix_d3_start>,
  end_label: <appendix_d3_end>,
)

#let appendix_d4_meta = (
  number: [4],
  code_key: "d4",
  start_label: <appendix_d4_start>,
  end_label: <appendix_d4_end>,
)

#let d1_content(thesis: (:), body) = appendix_content(
  appendix_d1_meta,
  thesis: thesis,
)[#body]

#let d2_content(thesis: (:), body) = appendix_content(
  appendix_d2_meta,
  thesis: thesis,
)[#body]

#let d3_content(thesis: (:), body) = appendix_content(
  appendix_d3_meta,
  thesis: thesis,
)[#body]

#let d4_content(thesis: (:), body) = appendix_content(
  appendix_d4_meta,
  thesis: thesis,
)[#body]
