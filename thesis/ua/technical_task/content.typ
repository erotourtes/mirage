#import "outline.typ": technical_task_outline_heading, technical_task_page_frame

#let technical_task_content(
  document-code: [todo],
) = {
  technical_task_page_frame()[

    #technical_task_outline_heading[
      todo
    ]
  ]
}
