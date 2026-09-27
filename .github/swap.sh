#!/bin/sh
# Swap for the native compile on GitHub's Linux runners (ci.yml): clang
# takes about 20 GB to compile the app's C and the runners have 16. The
# swap file goes on /mnt when the runner has it, and never takes more than
# the free space less 8 GB (a full disk kills the runner).
set -eu
dir=/; [ -d /mnt ] && dir=/mnt
df -h / /mnt || true
free_gb=$(df -BG --output=avail "$dir" | tail -1 | tr -dc 0-9)
size=$(( free_gb - 8 )); [ "$size" -gt 16 ] && size=16
if [ "$size" -ge 2 ]; then
  sudo fallocate -l "${size}G" "$dir/swap-build"
  sudo chmod 600 "$dir/swap-build"
  sudo mkswap "$dir/swap-build"
  sudo swapon "$dir/swap-build"
else
  echo "only ${free_gb} GB free on $dir: no swap"
fi
free -h
