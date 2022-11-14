#!/usr/bin/env -S just --justfile
# Ibiyemi's cross-compiling Justfile, (c) 14 Nov 2022

# This is intended to create a working armv7l cross compiler that is suitable for generating binaries that will run on a Raspberry Pi.
# Tested on macOS 13 Ventura and Manjaro

# brew dependencies: remake libmpc mpfr isl gmp flex bison gawk
# apt dependencies: libmpfr-dev libmpc-dev libgmp-dev autotools-dev autoconf file rsync flex bison binutils gawk gcc g++ make python3
# pacman dependencies: gmp libisl mpfr 

# if everything is set up as intended you should be able to run "just
# download-all extract-all build-all" and get a working cross compiler in about
# 10 minutes

GLIBC_VERSION := "2.31"
BINUTILS_VERSION := "2.39"
LINUX_SERIES := "5.x"
LINUX_VERSION := "5.15.72"

# compiling with an older version like 8.5.0 would allow us to compile libc
# without --disable-werror, but it does not seem to be compatible w/ the homebrew versions of mpc/mpfr/isl

GCC_VERSION := "12.2.0"
TARGET_GCC := "armv7l-linux-gnueabihf"
TARGET_LINUX := "arm"

PWD := `pwd`
SRCDIR := PWD / 'src'
PREFIX := PWD / 'opt/cross'
PREFIX_INNER := PREFIX / TARGET_GCC
GMP_PATH := if os() == 'macos' { `brew --prefix gmp` } else { '' }
ISL_PATH := if os() == 'macos' { `brew --prefix isl` } else { '' }
MPFR_PATH := if os() == 'macos' { `brew --prefix mpfr` } else { '' }
MPC_PATH := if os() == 'macos' { `brew --prefix libmpc` } else { '' }

BINUTILS_OPTS := "--disable-nls --disable-multilib"
DEPS_PATH_OPTS := (
  (if ISL_PATH != "" { '--with-isl="' + ISL_PATH + '" ' } else { '' }) + 
  (if MPC_PATH != "" { '--with-mpc="' + MPC_PATH + '" ' } else { '' }) + 
  (if MPFR_PATH != "" { '--with-mpfr="' + MPFR_PATH + '" ' } else { '' }) + 
  (if GMP_PATH != "" { '--with-gmp="' + GMP_PATH + '" ' } else { '' })
)
BINUTILS_OPTS_FULL := BINUTILS_OPTS + " " + DEPS_PATH_OPTS

GCC_OPTS_BASE := "--enable-languages=c,c++ --disable-multilib --disable-nls"
GCC_OPTS_EXT := "--with-float=hard"
GCC_OPTS_FULL := GCC_OPTS_BASE + " " + GCC_OPTS_EXT + " " + DEPS_PATH_OPTS

GLIBC_CPPFLAGS := "-mfloat-abi=hard -mfpu=vfp3 -march=armv7-a"
GLIBC_S1_OPTS := "--disable-multilib --disable-nls --disable-werror libc_cv_forced_unwind=yes"

PATH_EXT := (PREFIX / "bin") + (if os() == 'macos' { 
  ":" + (`brew --prefix gnu-sed` / "libexec/gnubin")  +
  ":" + (`brew --prefix bison` / "bin") +
  ":" + (`brew --prefix flex` / "bin")
} else {
  ""
})

# at the time of writing, the version of make available from homebrew was 4.4
# and this version of make seemed to have issues that made it not work properly
# whenever the -j flag was used, so i worked around this by installing remake
# instead, which is version 4.3 and does not have these issues
MAKE := if os() == 'macos' { "remake" } else { "make" }

default:

nuke:
  rm -rf binutils-{{BINUTILS_VERSION}}
  rm -rf gcc-{{GCC_VERSION}}
  rm -rf glibc-{{GLIBC_VERSION}}
  rm -rf linux-{{LINUX_VERSION}}

clean:
  #!/usr/bin/env bash
  set -uxo pipefail
  rm -r {{SRCDIR}}/binutils-{{BINUTILS_VERSION}}/build
  rm -r {{SRCDIR}}/gcc-{{GCC_VERSION}}/build
  rm -r {{SRCDIR}}/glibc-{{GLIBC_VERSION}}/build

build-all: build-binutils build-headers build-gcc build-glibc-s1 build-libgcc build-glibc-s2

build-binutils:
  #!/usr/bin/env bash
  export PATH="{{PATH_EXT}}:$PATH"
  set -euxo pipefail
  cd {{SRCDIR}}/binutils-{{BINUTILS_VERSION}}
  mkdir -p build
  cd build
  ../configure --prefix={{PREFIX}} --target={{TARGET_GCC}} {{BINUTILS_OPTS_FULL}}
  {{MAKE}} -j
  {{MAKE}} install

build-headers:
  #!/usr/bin/env bash
  set -euxo pipefail
  export PATH="{{PATH_EXT}}:$PATH"
  cd {{SRCDIR}}/linux-{{LINUX_VERSION}}
  {{MAKE}} ARCH={{TARGET_LINUX}} INSTALL_HDR_PATH={{PREFIX_INNER}} headers_install

build-gcc:
  #!/usr/bin/env bash
  set -euxo pipefail
  export PATH="{{PATH_EXT}}:$PATH"
  cd {{SRCDIR}}/gcc-{{GCC_VERSION}}
  mkdir -p build
  cd build
  ../configure --prefix={{PREFIX}} --target={{TARGET_GCC}} --with-headers={{PREFIX_INNER}}/include {{GCC_OPTS_FULL}}
  {{MAKE}} -j all-gcc
  {{MAKE}} install-gcc

build-glibc-s1:
  #!/usr/bin/env bash
  export PATH="{{PATH_EXT}}:$PATH"
  set -euxo pipefail
  cd {{SRCDIR}}/glibc-{{GLIBC_VERSION}}
  mkdir -p build
  cd build
  export CPPFLAGS="{{GLIBC_CPPFLAGS}}"
  ../configure --prefix={{PREFIX_INNER}} --host={{TARGET_GCC}} --target={{TARGET_GCC}} --with-headers={{PREFIX_INNER}}/include {{GLIBC_S1_OPTS}}
  {{MAKE}} install-bootstrap-headers=yes install-headers
  {{MAKE}} -j csu/subdir_lib
  install csu/crt1.o csu/crti.o csu/crtn.o {{PREFIX_INNER}}/lib
  {{TARGET_GCC}}-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o {{PREFIX_INNER}}/lib/libc.so
  touch {{PREFIX_INNER}}/include/gnu/stubs.h

build-libgcc:
  #!/usr/bin/env bash
  export PATH="{{PATH_EXT}}:$PATH"
  set -euxo pipefail
  cd {{SRCDIR}}/gcc-{{GCC_VERSION}}/build
  {{MAKE}} -j all-target-libgcc
  {{MAKE}} install-target-libgcc

build-glibc-s2:
  #!/usr/bin/env bash
  export PATH="{{PATH_EXT}}:$PATH"
  set -euxo pipefail
  cd {{SRCDIR}}/glibc-{{GLIBC_VERSION}}/build
  {{MAKE}} -j
  {{MAKE}} install

extract-all: extract-binutils extract-headers extract-gcc extract-glibc

extract-gcc:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && tar -xf gcc-{{GCC_VERSION}}.tar.xz

extract-binutils:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && tar -xf binutils-{{BINUTILS_VERSION}}.tar.xz

extract-headers:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && tar -xf linux-{{LINUX_VERSION}}.tar.xz

extract-glibc:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && tar -xf glibc-{{GLIBC_VERSION}}.tar.xz

download-all: download-gcc download-binutils download-glibc download-headers

download-glibc:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && curl -f -O https://ftp.gnu.org/gnu/glibc/glibc-{{GLIBC_VERSION}}.tar.xz

download-headers:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && curl -f -O https://mirrors.edge.kernel.org/pub/linux/kernel/v{{LINUX_SERIES}}/linux-{{LINUX_VERSION}}.tar.xz

download-gcc:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && curl -f -O https://gcc.gnu.org/pub/gcc/releases/gcc-{{GCC_VERSION}}/gcc-{{GCC_VERSION}}.tar.xz
  
download-binutils:
  mkdir -p {{SRCDIR}} && cd {{SRCDIR}} && curl -f -O https://ftp.gnu.org/gnu/binutils/binutils-{{BINUTILS_VERSION}}.tar.xz

