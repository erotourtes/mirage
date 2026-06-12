#!/usr/bin/env fish

set -l current_file_path (status current-filename)
set -l current_file_dir (dirname $current_file_path)
set -l root_dir (realpath "$current_file_dir/..")

set -l url "https://github.com/erotourtes/mirage"

qrencode -o "$root_dir/thesis/pictures/qr.png" \
    --size 10 \
    --level H \
    --margin 0 \
    $url
oxipng -o max --strip safe --out "$root_dir/thesis/pictures/output.png" "$root_dir/thesis/pictures/qr.png"
mv "$root_dir/thesis/pictures/output.png" "$root_dir/thesis/pictures/qr.png"
