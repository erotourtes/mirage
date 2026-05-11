#import "../front_matter/album_description.typ": album_description_page
#import "../front_matter/assignment.typ": (
  assignment_pages, default_assignment_meta,
)
#import "../front_matter/title.typ": default_title_meta, title_page
#import "../front_matter/annotation.typ": annotation_page
#import "heading.typ": heading_config
#import "theme.typ": figure_caption_rules


#let thesis_template(
  doc,
  thesis: none,
) = [
  #show: figure_caption_rules
  #set heading(numbering: "1.1", hanging-indent: 0pt)
  #show heading.where(level: 1): it => heading_config(level: 1, it: it)
  #show heading.where(level: 2): it => heading_config(level: 2, it: it)
  #show heading.where(level: 3): it => heading_config(level: 3, it: it)
  // adds spacing between list items
  #show selector.or(list.item): block
  #set text(lang: "uk", region: "UA")
  #show figure.where(kind: table): set block(breakable: true)

  #title_page(
    meta: default_title_meta,
    topic: thesis.topic,
    student_course: thesis.student.course,
    student_group: thesis.student.group,
    student_name: thesis.student.full_name,
    advisor_name: thesis.advisor.title_line,
    consultant_name: thesis.consultant.title_line,
    reviewer_name: thesis.reviewer.title_line,
    head_name: thesis.document.head_name,
    city: thesis.document.city,
    year: thesis.document.year,
    student_female: false,
  )

  #let long_form = code => {
    let form = code.form
    if form.note == none {
      lower(form.title)
    } else {
      lower([#form.title (#form.note)])
    }
  }

  #assignment_pages(
    meta: default_assignment_meta,
    topic: thesis.topic,
    student_name: thesis.student.full_name,
    student_name_genitive: thesis.student.genitive_name,
    advisor_name: thesis.advisor.sign_name,
    advisor_line: thesis.advisor.full_name,
    head_name: thesis.document.head_name,
    order_line: thesis.assignment.order_line,
    due_date: thesis.assignment.due_date,
    input_data: thesis.assignment.input_data,
    graphics: [
      #long_form(thesis.document.codes.d1),
      #long_form(thesis.document.codes.d2),
      #long_form(thesis.document.codes.d3),
    ],
    norm_controller: thesis.document.norm_controller,
    issue_date: thesis.assignment.issue_date,
    calendar: thesis.assignment.calendar,
    student_sign_name: thesis.student.sign_name,
    advisor_sign_name: thesis.advisor.sign_name,
    year: thesis.document.year,
  )

  #annotation_page(
    text_ua: thesis.annotation.text_ua,
    text_en: thesis.annotation.text_en,
  )

  #album_description_page(
    topic: thesis.topic,
    group: thesis.student.group,
    codes: thesis.document.codes,
    implemented_by: thesis.album_description.implemented_by,
    examined_by: thesis.album_description.examined_by,
  )

  #doc
]

// На ілюстрації дають посилання типу “рис. 1.2” чи “(рис. 1.2)”.
// Посилання на раніше згадувані ілюстрації даються за типом “див. рис. 1.2”.
#let fig_ref(target, see: false, parens: false) = {
  let content = if see {
    ref(target, supplement: [див. рис.])
  } else {
    ref(target, supplement: [рис.])
  }

  if parens {
    [(#content)]
  } else {
    content
  }
}

// На таблицю даються посилання типу “у таблиці 2.12”.
// На раніше згадувані таблиці дають посилання типу “див. таблицю 2.12”.
#let table_ref(target, see: false, parens: false, custom: none) = {
  let content = if custom != none {
    ref(target, supplement: custom)
  } else if see {
    [#ref(target, supplement: [див. таблицю])]
  } else {
    [#ref(target, supplement: [у таблиці])]
  }

  if parens {
    [(#content)]
  } else {
    content
  }
}

#let llink(..args) = {
  let content = link(..args)
  show link: underline

  content
}
