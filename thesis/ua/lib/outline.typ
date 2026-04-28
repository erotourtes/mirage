#import "page.typ": outline_page_frame
#import "footer.typ": footer_f2, footer_f2a

#let outline_entry_row(entry) = [
  #let page-number = counter(page).at(entry.location()).first()
  #let heading-number = if entry.numbering == none {
    []
  } else {
    [#numbering(entry.numbering, ..counter(heading).at(entry.location())) ]
  }
  #link(entry.location())[
    #grid(
      columns: (auto, 1fr, auto),
      column-gutter: 1.6mm,
      [#pad(left: 11mm * calc.max(entry.level - 1, 0))[
        #heading-number #entry.body
      ]],
      [#box(width: 100%, clip: true)[#repeat()[.]]],
      [#page-number],
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
  document-code: [todo],
  implemented-by: [todo],
  reviewed-by: [todo],
  norm-controller: [],
  approved-by: [],
  start-label: none,
  end-label: none,
  header-label: none,
) = context {
  counter(page).update(1)

  let entries = query(selector(heading).and(header-label))
  let sheet-count = context {
    let starts = query(start-label)
    let ends = query(end-label)

    if starts.len() == 0 or ends.len() == 0 {
      [??]
    } else {
      let start-page = starts.first().location().page()
      let end-page = ends.last().location().page()

      end-page - start-page + 1
    }
  }

  outline_page_frame(
    footer: context {
      let p = counter(page).get().first()
      if p == 1 {
        footer_f2(
          topic: topic,
          group: group,
          document-code: document-code,
          sheet-number: [1],
          sheet-count: [#sheet-count],
          implemented-by: implemented-by,
          reviewed-by: reviewed-by,
          norm-controller: norm-controller,
          approved-by: approved-by,
        )
      } else {
        footer_f2a()
      }
    },
  )[
    #metadata("start") #start-label

    #align(center)[ЗМІСТ]
    #v(7mm)

    #for (index, entry) in entries.enumerate() [
      #outline_entry_row(entry)
      #v(outline_entry_gap(entries, index))
    ]
  ]
}
