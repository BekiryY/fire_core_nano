#!/usr/bin/env bash
# ============================================================
#  package.sh [PREFIX] -- the prebuilt toolchain as a release tarball
#
#  Strips the host programs, adds the patches, sources.sha512 and the README (GPL: the
#  corresponding source is the upstream tarballs in sources.sha512 plus patches/), and writes
#  riscv32-nano-elf-<date>-x86_64-linux.tar.xz next to this script. Unpack anywhere:
#    tar xf riscv32-nano-elf-*.tar.xz && export PATH=$PWD/riscv32-nano/bin:$PATH
# ============================================================
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${1:-${PREFIX:-$HOME/opt/riscv32-nano}}
NAME=riscv32-nano-elf-$(date +%Y%m%d)-$(uname -m)-linux
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp -a "$PREFIX" "$WORK/riscv32-nano"
R=$WORK/riscv32-nano
rm -rf "$R/share/info" "$R/share/man" "$R/lib/gcc/riscv32-nano-elf/"*/plugin
find "$R/bin" "$R/libexec" "$R/riscv32-nano-elf/bin" -type f -perm -u+x \
  -exec sh -c 'file -b "$1" | grep -q "^ELF" && strip "$1"' _ {} \;
mkdir -p "$R/share/riscv32-nano"
cp -a "$HERE/README.md" "$HERE/sources.sha512" "$HERE/build.sh" "$HERE/patches" "$R/share/riscv32-nano/"
tar -C "$WORK" -cJf "$HERE/$NAME.tar.xz" riscv32-nano
ls -la "$HERE/$NAME.tar.xz"
sha512sum "$HERE/$NAME.tar.xz" | tee "$HERE/$NAME.tar.xz.sha512"
