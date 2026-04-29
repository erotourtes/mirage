#import "page.typ": bordered_page
#import "footer.typ": footer_f2, footer_f2a

#let outline_entry_row(entry) = [
  #let page_number = counter(page).at(entry.location()).first()
  #let heading_number = if entry.numbering == none {
    []
  } else {
    [#numbering(entry.numbering, ..counter(heading).at(entry.location())) ]
  }
  #link(entry.location())[
    #grid(
      columns: (auto, 1fr, auto),
      column-gutter: 1.6mm,
      [#pad(left: 11mm * calc.max(entry.level - 1, 0))[
        #heading_number #entry.body
      ]],
      [#box(width: 100%, clip: true)[#repeat()[.]]],
      [#page_number],
    )
  ]
]

#let outline_entry_gap(entries, index) = {
  if index + 1 >= entries.len() {
    0mm
  } else {
    let entry = entries.at(index)
    let next = entries.at(index + 1)

    if next.level > entry.level {
      2mm
    } else if entry.level == 1 {
      3mm
    } else {
      2mm
    }
  }
}


#let outline_page(
  topic: none,
  group: none,
  document_code: [todo],
  implemented_by: [todo],
  reviewed_by: [todo],
  norm_controller: [],
  approved_by: [],
  start_label: none,
  end_label: none,
  header_label: none,
) = context {
  counter(page).update(1)

  let entries = query(selector(heading).and(header_label))
  let sheet_count = context {
    let starts = query(start_label)
    let ends = query(end_label)

    if starts.len() == 0 or ends.len() == 0 {
      [??]
    } else {
      let start_page = starts.first().location().page()
      let end_page = ends.last().location().page()

      end_page - start_page + 1
    }
  }
  let first_footer = footer_f2(
    topic: topic,
    group: group,
    document_code: document_code,
    sheet_number: [1],
    sheet_count: [#sheet_count],
    implemented_by: implemented_by,
    reviewed_by: reviewed_by,
    norm_controller: norm_controller,
    approved_by: approved_by,
  )

  bordered_page(
    footer_space: measure(first_footer).height,
    footer: context {
      let p = counter(page).get().first()
      if p == 1 {
        first_footer
      } else {
        footer_f2a(document_code: document_code)
      }
    },
  )[
    #metadata("start") #start_label

    #align(center)[ЗМІСТ]
    #v(7mm)

    #for (index, entry) in entries.enumerate() [
      #outline_entry_row(entry)
      #v(outline_entry_gap(entries, index))
    ]
  ]
}
