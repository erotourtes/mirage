#import "../front_matter/album_description.typ": album_description_page
#import "../front_matter/assignment.typ": assignment_pages
#import "../front_matter/title.typ": title_page
#import "../front_matter/annotation.typ": annotation_page

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
    #if level > 1 and it.numbering != none {
      numbering(it.numbering, ..counter(heading).at(it.location()))
    }
    #it.body
  ]
}


#let thesis_template(
  thesis: (:),
  doc,
) = [
  #set heading(numbering: "1.1")
  #show heading.where(level: 1): it => heading_config(1, it)
  #show heading.where(level: 2): it => heading_config(2, it)
  #show heading.where(level: 3): it => heading_config(3, it)

  #title_page(
    topic: thesis.topic,
    student_course: thesis.student.course,
    student_group: thesis.student.group,
    student_name: thesis.student.full_name,
    advisor_name: thesis.advisor.title_line,
    head_name: thesis.document.head_name,
    city: thesis.document.city,
    year: thesis.document.year,
  )

  #assignment_pages(
    topic: thesis.topic,
    student_name: thesis.student.full_name,
    student_name_genitive: thesis.student.genitive_name,
    advisor_name: thesis.advisor.sign_name,
    advisor_line: thesis.advisor.full_name,
    head_name: thesis.document.head_name,
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
  )

  #doc
]
