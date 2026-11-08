# riscv32-nano-elf: the C toolchain for the nano cores

The nano cores have 6 registers: `x0`, `ra`, `sp`, `a0`, `a1`, `a2`. A stock RISC-V compiler
assumes 16 (RV32E) and puts arguments, temporaries and saved values in registers these
cores do not have. **`-mnano`** is a GCC option (a patch to GCC 13.2.0) that compiles C for
exactly those 6 registers, with a calling convention that works for any C function:

| | `-mnano` |
|---|---|
| Argument registers | `a0`, `a1`, `a2` (the rest go on the stack) |
| Return value | `a0` (`a0:a1` for 64-bit values) |
| An argument split between `a2` and the stack | never: the first argument that does not fit and all later ones go on the stack |
| Variadic arguments (`printf`) | always on the stack |
| Callee-saved registers | none (all of `ra`, `a0`..`a2` are caller-saved) |
| Indirect calls | through `ra` (`lw ra, ...; jalr ra`) |
| Frame pointer | none: `alloca` and variable-length arrays are a compile error |
| Predefined macro | `__riscv_nano` |

Requires `-march=rv32e -mabi=ilp32e` (the defaults of this compiler). `-msave-restore` is
rejected.

The toolchain consists of:

- **binutils 2.42**, unmodified.
- **GCC 13.2.0**, C only, with [`patches/gcc-13.2.0-mnano.patch`](patches/gcc-13.2.0-mnano.patch).
- **libgcc**, built with `-Os -mnano`. It has 6-register assembly for multiply and divide and a small 64-bit division (0.5 KiB instead of 3.8 KiB). There is no unwinder.
- **picolibc 1.8.10** with [`patches/picolibc-1.8.10-mnano.patch`](patches/picolibc-1.8.10-mnano.patch).
  - `memcpy`, `memmove`, `memset`, `strcmp` and `setjmp`/`longjmp` get nano assembly versions.
  - Built single-threaded, without TLS and without atomics.
  - Integer-only `printf` by default.

## Install

### Prebuilt (x86_64 Linux, WSL)

Download `riscv32-nano-elf-<date>-x86_64-linux.tar.xz` from the GitHub release, then:

```sh
tar xf riscv32-nano-elf-*-x86_64-linux.tar.xz -C $HOME/opt
export PATH=$HOME/opt/riscv32-nano/bin:$PATH
riscv32-nano-elf-gcc --version
```

### From source

```sh
./build.sh                                  # fetch, binutils, gcc, picolibc
PREFIX=/opt/riscv32-nano J=8 ./build.sh     # another install dir, 8 parallel jobs
```

- **Build host:** Linux or WSL.
- **Packages:** `gcc g++ make bison flex python3 meson ninja-build curl xz-utils bzip2 patch`.
- **Time:** about 30 minutes with 8 jobs.
- **Sources:** downloaded into `$SRC` (default `~/src/riscv32-nano`) and checked against [`sources.sha512`](sources.sha512) before anything is built.
- **Stages:** each one can be run alone, for example `./build.sh picolibc`.

`package.sh` turns an install into the release tarball.

### Test

```sh
test/run_tests.sh               # PREFIX=... for another install
```

The test builds `test/abi.c` and `test/libc.c` at `-O0`, `-O2` and `-Os`. Each build passes only if:

- every instruction uses only `x0 ra sp a0 a1 a2`;
- the program passes on [Spike](https://github.com/riscv-software-src/riscv-isa-sim) (`--isa=rv32e`). This step runs only when `spike` is on PATH.

## Use

The board support and example programs are in [`../sw`](../sw):

```sh
cd ../sw && make                 # examples/hello for the FPGA subsystem
```

Directly:

```sh
riscv32-nano-elf-gcc -march=rv32e -mabi=ilp32e -mnano -Os -nostdlib -T link.ld crt0.S main.c \
    -Wl,--start-group -lc -lgcc -Wl,--end-group -o main.elf
```

### Limits

- **Code size.** Everything is a stack access with 6 registers, so code is 10-20 % larger than RV32E, and the example subsystems have 2 KiB of RAM.
  - picolibc's `printf` is 1.4 KiB (minimal), 2.4 KiB (integer, the default) or 4.8 KiB (double).
  - `sw/bsp/printf_tiny.c` is about 0.8 KiB.
- **Multiply and divide** are software (libgcc), because the cores are RV32E without M.
- **No `alloca` or VLAs** (there is no frame pointer).
- **No C++ and no threads.**
- **Hard-to-allocate functions.** If GCC cannot fit a function into 4 allocatable registers, it stops with `register allocation does not converge in 'f'` instead of looping. Use `-O1` for that file, or split the function.
  - `-mnano` turns off `-fcse-follow-jumps` by default. That optimization keeps constants live across branches, and that was what made picolibc's math and stdio code fail to converge.

## License

- **GCC and binutils:** GPLv3. The patches are GPLv3 as part of GCC.
- **picolibc:** BSD-style licenses, see its `COPYING.picolibc`.
- **The prebuilt tarball:** its corresponding source is the upstream tarballs listed in `sources.sha512` plus `patches/`. Both are inside the tarball under `share/riscv32-nano/` and in this directory.
- **The scripts in this directory:** MIT, like the rest of the repository.
