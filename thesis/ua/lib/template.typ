#import "../front_matter/album_description.typ": album_description_page
#import "../front_matter/assignment.typ": assignment_pages
#import "../front_matter/title.typ": title_page

#let heading_config(level, it) = {
  let size = if level == 1 {
    18pt
  } else if level == 2 {
    16pt
  } else {
    14pt
  }

  text(
    size: size,
    weight: "bold",
  )[
    #if it.numbering != none {
      numbering(it.numbering, ..counter(heading).at(it.location()))
    }
    #it.body
  ]
}


#let thesis_template(
  document_meta: (:),
  thesis: (:),
  doc,
) = [
  #set heading(numbering: "1")
  #show heading.where(level: 1): it => heading_config(1, it)
  #show heading.where(level: 2): it => heading_config(2, it)
  #show heading.where(level: 3): it => heading_config(3, it)

  #title_page(
    topic: thesis.topic,
    student_course: thesis.student_course,
    student_group: thesis.student_group,
    student_name: thesis.student_name,
    advisor_name: thesis.advisor_title_line,
    head_name: document_meta.head_name,
    city: document_meta.city,
    year: document_meta.year,
  )

  #assignment_pages(
    topic: thesis.topic,
    student_name: thesis.student_name,
    student_name_genitive: thesis.student_name_genitive,
    advisor_name: thesis.advisor_sign_name,
    advisor_line: thesis.advisor_full_line,
    head_name: document_meta.head_name,
    student_sign_name: thesis.student_sign_name,
    advisor_sign_name: thesis.advisor_sign_name,
    year: document_meta.year,
  )

  #album_description_page(
    topic: thesis.topic,
    group: thesis.student_group,
  )

  #doc
]
