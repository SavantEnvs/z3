#!/usr/bin/env bash
#
# mayhem/build.sh — build Z3's fuzz harnesses (sanitized, instrumented libz3) and the oracle `z3` binary.
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. Re-runnable and offline:
# Z3's CMake build fetches nothing.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

TARGETS="fuzz_smt2_eval fuzz_smt2_parse fuzz_dimacs fuzz_optimize fuzz_tactic"

# 1) libz3 (static), sanitized + SanCov-instrumented + DWARF 3. `-fsanitize=fuzzer-no-link` is
#    unconditional so the library carries coverage even when SANITIZER_FLAGS is empty.
#    Release = -O1 -DNDEBUG (SASSERT off); build dirs match upstream's `*build*/**` .gitignore.
#    The library carries line tables only (still DWARF 3): full variable/location DWARF for Z3's ~700 TUs
#    makes every binary ~600 MB. The harness objects below keep the full $DEBUG_FLAGS.
FUZZ_FLAGS="$SANITIZER_FLAGS -gline-tables-only -gdwarf-3 -fsanitize=fuzzer-no-link"
cmake -S "$SRC" -B "$SRC/build-fuzz" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
    -DCMAKE_C_FLAGS_RELEASE="-O1 -DNDEBUG" -DCMAKE_CXX_FLAGS_RELEASE="-O1 -DNDEBUG" \
    -DBUILD_SHARED_LIBS=OFF -DZ3_BUILD_PYTHON_BINDINGS=OFF -DZ3_USE_LIB_GMP=OFF \
    -DZ3_INCLUDE_GIT_HASH=OFF -DZ3_INCLUDE_GIT_DESCRIBE=OFF
cmake --build "$SRC/build-fuzz" --target libz3 -j"$MAYHEM_JOBS"

# 2) Harnesses: each linked once with libFuzzer and once with the run-once standalone driver
#    (a C object, so its LLVMFuzzerTestOneInput reference keeps C linkage). lsan_off.cc disables LSan.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$SRC/build-fuzz/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$SRC/build-fuzz/lsan_off.o"
for t in $TARGETS; do
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC/src/api" -c "$SRC/mayhem/$t.cpp" -o "$SRC/build-fuzz/$t.o"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
        "$SRC/build-fuzz/$t.o" "$SRC/build-fuzz/lsan_off.o" "$SRC/build-fuzz/libz3.a" -lpthread -o "$SRC/$t"
    $CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
        "$SRC/build-fuzz/$t.o" "$SRC/build-fuzz/standalone_main.o" "$SRC/build-fuzz/lsan_off.o" \
        "$SRC/build-fuzz/libz3.a" -lpthread -o "$SRC/$t-standalone"
done

# 3) The oracle: the real `z3` binary with the project's NORMAL flags (no sanitizers, default Release).
cmake -S "$SRC" -B "$SRC/build-test" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DBUILD_SHARED_LIBS=OFF -DZ3_BUILD_PYTHON_BINDINGS=OFF -DZ3_USE_LIB_GMP=OFF \
    -DZ3_INCLUDE_GIT_HASH=OFF -DZ3_INCLUDE_GIT_DESCRIBE=OFF
cmake --build "$SRC/build-test" --target shell -j"$MAYHEM_JOBS"
test -x "$SRC/build-test/z3"
