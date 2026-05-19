#!/usr/bin/env fish

set -l current_file_path (status current-filename)
set -l current_file_dir (dirname $current_file_path)
set -l root_dir (realpath "$current_file_dir/..")
set -l line_width 80

set -l paths (fd . --type file -e typ "$current_file_dir/../thesis" -a)

echo "Formatting files:"
for path in $paths
    set -l rel_path (string replace "$root_dir/" "" $path)
    echo "  $rel_path"
    typstyle -i $path --wrap-text --line-width $line_width
    switch $rel_path
        case thesis/main.typ thesis/ua/main.typ
            python3 "$current_file_dir/reflow-typst-prose.py" --line-width $line_width $path
    end
end
