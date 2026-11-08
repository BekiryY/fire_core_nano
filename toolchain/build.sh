#!/usr/bin/env bash
# ============================================================
#  build.sh [stage ...] -- builds riscv32-nano-elf, the -mnano toolchain for the nano cores
#
#  Stages (default: all, in this order):
#    fetch     download the sources into $SRC and check them against sources.sha512
#    binutils  binutils 2.42 for riscv32-nano-elf (unpatched)
#    gcc       GCC 13.2.0 + patches/gcc-13.2.0-mnano.patch: C compiler and libgcc (-Os -mnano)
#    picolibc  picolibc 1.8.10 + patches/picolibc-1.8.10-mnano.patch (-Os -mnano)
#
#  Env:  PREFIX  install dir             (default $HOME/opt/riscv32-nano)
#        SRC     download + build dir    (default $HOME/src/riscv32-nano)
#        J       parallel jobs           (default nproc)
#        GNU_MIRROR                      (default https://ftpmirror.gnu.org)
#  Needs: a Linux host (or WSL) with gcc, g++, make, bison, flex, python3, meson >= 0.62,
#  ninja, curl, xz, bzip2, patch (no texinfo: MAKEINFO=true skips the manuals).
#  Result: $PREFIX/bin/riscv32-nano-elf-{gcc,as,ld,objdump,...}, picolibc in
#  $PREFIX/riscv32-nano-elf/{include,lib}. Takes about 20 min on 16 cores.
# ============================================================
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$HOME/opt/riscv32-nano}
SRC=${SRC:-$HOME/src/riscv32-nano}
J=${J:-$(nproc)}
GNU_MIRROR=${GNU_MIRROR:-https://ftpmirror.gnu.org}
T=riscv32-nano-elf

BINUTILS=binutils-2.42
GCC=gcc-13.2.0
PICOLIBC=picolibc-1.8.10
URLS=(
  "$GNU_MIRROR/binutils/$BINUTILS.tar.xz"
  "$GNU_MIRROR/gcc/$GCC/$GCC.tar.xz"
  "https://gcc.gnu.org/pub/gcc/infrastructure/gmp-6.2.1.tar.bz2"
  "https://gcc.gnu.org/pub/gcc/infrastructure/mpfr-4.1.0.tar.bz2"
  "https://gcc.gnu.org/pub/gcc/infrastructure/mpc-1.2.1.tar.gz"
  "https://github.com/picolibc/picolibc/releases/download/1.8.10/$PICOLIBC.tar.xz"
)
# GCC's own prerequisite versions (contrib/download_prerequisites); isl is not used.

# Host programs fully static: the tarball runs on any x86_64 Linux (any glibc) and in WSL.
HOST_LDFLAGS=${HOST_LDFLAGS:---static}    # --static: libtool drops a plain -static

say() { printf '\n==== %s\n' "$*"; }

fetch() {
  say "fetch -> $SRC"
  mkdir -p "$SRC"; cd "$SRC"
  for u in "${URLS[@]}"; do
    f=${u##*/}
    if [ ! -f "$f" ]; then curl -fL --retry 3 -o "$f.part" "$u"; mv "$f.part" "$f"; fi
  done
  sha512sum -c "$HERE/sources.sha512"
}

build_binutils() {
  say "binutils -> $PREFIX"
  cd "$SRC"; rm -rf "$BINUTILS" build-binutils
  tar xf "$BINUTILS.tar.xz"
  mkdir build-binutils; cd build-binutils
  "../$BINUTILS/configure" --target=$T --prefix="$PREFIX" \
    --disable-nls --disable-werror --disable-gdb --disable-gdbserver --disable-sim \
    --disable-gprofng --disable-plugins --disable-shared --without-zstd --without-debuginfod \
    LDFLAGS="$HOST_LDFLAGS" MAKEINFO=true
  make -j"$J" MAKEINFO=true
  make install MAKEINFO=true
}

build_gcc() {
  say "gcc -> $PREFIX"
  cd "$SRC"; rm -rf "$GCC" build-gcc
  tar xf "$GCC.tar.xz"
  for p in gmp-6.2.1.tar.bz2 mpfr-4.1.0.tar.bz2 mpc-1.2.1.tar.gz; do
    tar xf "$p"; d=${p%.tar.*}; mv "$d" "$GCC/${d%%-*}"
  done
  (cd "$GCC" && patch -p1 < "$HERE/patches/$GCC-mnano.patch")
  export PATH=$PREFIX/bin:$PATH
  mkdir build-gcc; cd build-gcc
  # libgcc at -Os: at -O2 GCC's register allocator never converges on _powitf2 with
  # three argument registers; -Os also keeps the helpers small.
  "../$GCC/configure" --target=$T --prefix="$PREFIX" \
    --with-arch=rv32e --with-abi=ilp32e --disable-multilib \
    --enable-languages=c --without-headers --with-newlib \
    --disable-shared --disable-threads --disable-tls --disable-nls --without-isl \
    --disable-libssp --disable-libquadmath --disable-libgomp --disable-libatomic \
    --disable-gcov --disable-bootstrap --disable-plugin --disable-lto --without-zstd \
    --with-pkgversion="FireCore nano -mnano" \
    LDFLAGS="$HOST_LDFLAGS" CFLAGS_FOR_TARGET="-Os -mnano" MAKEINFO=true
  make -j"$J" all-gcc MAKEINFO=true
  make -j"$J" all-target-libgcc MAKEINFO=true
  make install-gcc install-target-libgcc MAKEINFO=true
}

build_picolibc() {
  say "picolibc -> $PREFIX/$T"
  cd "$SRC"; rm -rf "$PICOLIBC" build-picolibc
  tar xf "$PICOLIBC.tar.xz"
  (cd "$PICOLIBC" && patch -p1 < "$HERE/patches/$PICOLIBC-mnano.patch")
  export PATH=$PREFIX/bin:$PATH
  mkdir build-picolibc; cd build-picolibc
  cat > cross.txt <<EOF
[binaries]
c = ['$T-gcc', '-nostdlib']
ar = '$T-ar'
as = '$T-as'
nm = '$T-nm'
strip = '$T-strip'

[host_machine]
system = 'unknown'
cpu_family = 'riscv32'
cpu = 'riscv'
endian = 'little'

[properties]
c_args = ['-march=rv32e', '-mabi=ilp32e', '-mnano']
c_link_args = ['-march=rv32e', '-mabi=ilp32e', '-mnano']
skip_sanity_check = true
EOF
  # Single thread, no TLS (tp is not a register on the nano cores), no atomics (no A
  # extension), no start-up code or semihosting (the BSP has both jobs), integer-only
  # printf by default (2 KiB of code on the example subsystems).
  meson setup --cross-file cross.txt --buildtype=minsize \
    --prefix="$PREFIX/$T" -Dincludedir=include -Dlibdir=lib -Dspecsdir=none \
    -Dmultilib=false -Dpicocrt=false -Dpicocrt-lib=false -Dsemihost=false -Dtests=false \
    -Dthread-local-storage=false -Dsingle-thread=true -Datomic-ungetc=false \
    -Dformat-default=integer -Dio-long-long=false -Dfast-strcmp=false \
    "../$PICOLIBC"
  ninja -j"$J"
  ninja install
}

[ $# -gt 0 ] || set -- fetch binutils gcc picolibc
for s in "$@"; do
  case $s in
    fetch)    fetch ;;
    binutils) build_binutils ;;
    gcc)      build_gcc ;;
    picolibc) build_picolibc ;;
    *) echo "build.sh: unknown stage '$s' (fetch binutils gcc picolibc)" >&2; exit 2 ;;
  esac
done
say "done: $("$PREFIX/bin/$T-gcc" --version | head -1)"
