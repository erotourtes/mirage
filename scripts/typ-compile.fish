#!/usr/bin/env fish

set -l current_file_path (status current-filename)
set -l current_file_dir (dirname $current_file_path)
set -l root_dir (realpath "$current_file_dir/..")
set -l thesis_dir "$root_dir/thesis"

typst compile "$thesis_dir/ua.typ" "$thesis_dir/ua.pdf" --root "$root_dir"

