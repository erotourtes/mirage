#import "outline.typ": technical_task_outline_heading, technical_task_page

#let technical_task_content(
  document_code: [todo],
) = {
  technical_task_page(document_code: document_code)[

    #technical_task_outline_heading[
      todo
    ]
  ]
}
