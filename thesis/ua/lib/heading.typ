#let heading_config(
  level: none,
  it: none,
  number_level_one: false,
) = {
  let size = if level == 1 {
    18pt
  } else if level == 2 {
    16pt
  } else {
    14pt
  }

  let should_number = it.numbering != none and (
    level > 1 or number_level_one
  )

  let heading_body = text(
    size: size,
    weight: "bold",
  )[
    #if should_number {
      numbering(it.numbering, ..counter(heading).at(it.location()))
      [ ]
    }
    #it.body
  ]

  if level == 1 {
    align(center)[#heading_body]
    v(8mm)
  } else {
    heading_body
  }
}
