#!/usr/bin/env fish

set -l current_file_path (status current-filename)
set -l current_file_dir (dirname $current_file_path)
set -l root_dir (realpath "$current_file_dir/..")

set -l paths (fd . --type file -e typ "$current_file_dir/../doc" -a)

echo "Formatting files:"
for path in $paths
    set -l rel_path (string replace "$root_dir/" "" $path)
    echo "  $rel_path"
    typstyle -i $path --wrap-text
end

