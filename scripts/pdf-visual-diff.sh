#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/pdf-visual-diff.sh [--dpi 150] [--fuzz 1%] [--open] OLD.pdf NEW.pdf [OUT_DIR]

Creates a visual PDF diff report at OUT_DIR/index.html.

Options:
  --dpi VALUE    Render DPI. Higher is slower but catches smaller changes. Default: 150
  --fuzz VALUE   ImageMagick fuzz tolerance. Default: 1%
  --open         Open the generated HTML report with the system opener.
  -h, --help     Show this help.

Example:
  scripts/pdf-visual-diff.sh thesis/ua/old_main.pdf thesis/ua/main.pdf tmp/pdf-diff
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

html_escape() {
  local value=$1
  value=${value//&/&amp;}
  value=${value//</&lt;}
  value=${value//>/&gt;}
  value=${value//\"/&quot;}
  printf '%s' "$value"
}

page_count() {
  pdfinfo "$1" | awk '/^Pages:/ { print $2; exit }'
}

render_pdf() {
  local pdf=$1
  local prefix=$2
  pdftocairo -png -r "$dpi" "$pdf" "$prefix"
}

page_png() {
  local prefix=$1
  local page=$2
  printf "%s-%0${page_digits}d.png" "$prefix" "$page"
}

make_blank_page() {
  local source=$1
  local target=$2
  local dimensions

  dimensions=$(magick identify -format '%wx%h' "$source")
  magick -size "$dimensions" xc:white "$target"
}

normalize_pair() {
  local left=$1
  local right=$2
  local normalized_left=$3
  local normalized_right=$4
  local left_size right_size left_width left_height right_width right_height width height

  left_size=$(magick identify -format '%w %h' "$left")
  right_size=$(magick identify -format '%w %h' "$right")
  read -r left_width left_height <<<"$left_size"
  read -r right_width right_height <<<"$right_size"

  width=$((left_width > right_width ? left_width : right_width))
  height=$((left_height > right_height ? left_height : right_height))

  magick -size "${width}x${height}" xc:white "$left" -gravity northwest -composite "$normalized_left"
  magick -size "${width}x${height}" xc:white "$right" -gravity northwest -composite "$normalized_right"
}

difference_metric() {
  local left=$1
  local right=$2
  local diff=$3
  local metric status

  set +e
  metric=$(magick compare -metric AE -fuzz "$fuzz" "$left" "$right" "$diff" 2>&1)
  status=$?
  set -e

  if [[ $status -gt 1 ]]; then
    die "ImageMagick compare failed for $left and $right: $metric"
  fi

  metric=${metric%% *}
  printf '%s' "${metric:-0}"
}

dpi=150
fuzz='1%'
open_report=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dpi)
      [[ $# -ge 2 ]] || die '--dpi requires a value'
      dpi=$2
      shift 2
      ;;
    --fuzz)
      [[ $# -ge 2 ]] || die '--fuzz requires a value'
      fuzz=$2
      shift 2
      ;;
    --open)
      open_report=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 2 && $# -le 3 ]] || {
  usage >&2
  exit 2
}

old_pdf=$1
new_pdf=$2
out_dir=${3:-pdf-visual-diff}

[[ -f $old_pdf ]] || die "old PDF not found: $old_pdf"
[[ -f $new_pdf ]] || die "new PDF not found: $new_pdf"

need_command pdfinfo
need_command pdftocairo
need_command magick

mkdir -p "$out_dir"/{old,new,normalized,diff}

old_pages=$(page_count "$old_pdf")
new_pages=$(page_count "$new_pdf")
[[ -n $old_pages && -n $new_pages ]] || die 'failed to read PDF page counts'

max_pages=$((old_pages > new_pages ? old_pages : new_pages))
page_digits=${#max_pages}
old_prefix="$out_dir/old/page"
new_prefix="$out_dir/new/page"

printf 'Rendering %s (%s pages) and %s (%s pages) at %s DPI...\n' "$old_pdf" "$old_pages" "$new_pdf" "$new_pages" "$dpi"
render_pdf "$old_pdf" "$old_prefix"
render_pdf "$new_pdf" "$new_prefix"

report="$out_dir/index.html"
pages_report="$out_dir/.pages.html.tmp"
changed_pages=0
total_changed_pixels=0

: >"$pages_report"

for page in $(seq 1 "$max_pages"); do
  old_page=$(page_png "$old_prefix" "$page")
  new_page=$(page_png "$new_prefix" "$page")
  old_missing=false
  new_missing=false

  if [[ ! -f $old_page ]]; then
    old_missing=true
    make_blank_page "$new_page" "$old_page"
  fi

  if [[ ! -f $new_page ]]; then
    new_missing=true
    make_blank_page "$old_page" "$new_page"
  fi

  normalized_old="$out_dir/normalized/page-${page}-old.png"
  normalized_new="$out_dir/normalized/page-${page}-new.png"
  diff_page="$out_dir/diff/page-${page}.png"
  normalize_pair "$old_page" "$new_page" "$normalized_old" "$normalized_new"

  metric=$(difference_metric "$normalized_old" "$normalized_new" "$diff_page")
  total_changed_pixels=$((total_changed_pixels + metric))

  class='same'
  label='same'
  if [[ $metric -ne 0 || $old_missing == true || $new_missing == true ]]; then
    class='changed'
    label='changed'
    changed_pages=$((changed_pages + 1))
  fi

  extra=''
  [[ $old_missing == true ]] && extra=' old page missing'
  [[ $new_missing == true ]] && extra=' new page missing'

  cat >>"$pages_report" <<EOF
    <section class="page $class">
      <h2>Page $page: $label · changed pixels: $metric$(html_escape "$extra")</h2>
      <div class="grid">
        <figure>
          <figcaption>Old</figcaption>
          <img src="normalized/page-$page-old.png" alt="Old page $page">
        </figure>
        <figure>
          <figcaption>New</figcaption>
          <img src="normalized/page-$page-new.png" alt="New page $page">
        </figure>
        <figure>
          <figcaption>Difference</figcaption>
          <img src="diff/page-$page.png" alt="Difference page $page">
        </figure>
      </div>
    </section>
EOF
done

unchanged_pages=$((max_pages - changed_pages))

cat >"$report" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>PDF visual diff</title>
  <style>
    body { margin: 0; font: 14px/1.4 system-ui, sans-serif; color: #111; background: #f6f6f6; }
    header { position: sticky; top: 0; z-index: 1; padding: 16px 20px; background: #fff; border-bottom: 1px solid #ddd; }
    main { padding: 20px; }
    h1 { margin: 0 0 8px; font-size: 20px; }
    .meta { color: #555; }
    .summary { display: flex; flex-wrap: wrap; gap: 8px 16px; margin-top: 10px; color: #333; }
    .controls { margin-top: 10px; }
    .controls label { display: inline-flex; align-items: center; gap: 6px; cursor: pointer; }
    body.hide-unchanged .page.same { display: none; }
    .page { margin: 0 0 24px; padding: 16px; background: #fff; border: 1px solid #ddd; }
    .page h2 { margin: 0 0 12px; font-size: 16px; }
    .changed h2 { color: #b00020; }
    .same h2 { color: #246b24; }
    .grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
    figure { margin: 0; }
    figcaption { margin: 0 0 6px; font-weight: 600; }
    img { display: block; width: 100%; height: auto; border: 1px solid #ccc; background: white; }
  </style>
</head>
<body>
  <header>
    <h1>PDF visual diff</h1>
    <div class="meta">Old: $(html_escape "$old_pdf") · New: $(html_escape "$new_pdf") · DPI: $(html_escape "$dpi") · Fuzz: $(html_escape "$fuzz")</div>
    <div class="summary">
      <span>Total pages: $max_pages</span>
      <span>Changed pages: $changed_pages</span>
      <span>Unchanged pages: $unchanged_pages</span>
      <span>Changed pixels: $total_changed_pixels</span>
    </div>
    <div class="controls">
      <label><input id="hide-unchanged" type="checkbox"> Hide unchanged pages</label>
    </div>
  </header>
  <main>
EOF

cat "$pages_report" >>"$report"

cat >>"$report" <<EOF
  </main>
  <script>
    document.getElementById('hide-unchanged').addEventListener('change', (event) => {
      document.body.classList.toggle('hide-unchanged', event.target.checked);
    });
  </script>
</body>
</html>
EOF
rm -f "$pages_report"

printf 'Compared %s pages. Changed pages: %s. Unchanged pages: %s. Changed pixels: %s.\n' "$max_pages" "$changed_pages" "$unchanged_pages" "$total_changed_pixels"
printf 'Report: %s\n' "$report"

if [[ $open_report == true ]]; then
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$report" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$report"
  else
    die 'no supported system opener found'
  fi
fi
