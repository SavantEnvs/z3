#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral known-answer oracle for Z3. Runs the real `z3` binary that mayhem/build.sh
# built (build-test/z3, project's normal flags) on fixed SMT-LIB2 / DIMACS inputs and compares its
# stdout to exact expected values (sat/unsat verdicts, models, simplifier results, optimum values,
# unsat cores). A patch that makes z3 exit early or print wrong answers fails. Does not compile.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

Z="$SRC/build-test/z3"
[ -x "$Z" ] || { echo "missing $Z: mayhem/build.sh must build it" >&2; emit_ctrf "z3-smt2-kat" 0 1; exit 1; }

passed=0; failed=0
check() {  # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); echo "PASS $1"
  else failed=$((failed+1)); echo "FAIL $1"; echo "  expected: $(printf %q "$2")"; echo "  actual:   $(printf %q "$3")"; fi
}
smt() {    # smt <name> <expected stdout> <smt2 input>
  local out; out=$(printf '%s\n' "$3" | timeout 120 "$Z" -in -smt2 2>&1)
  check "$1" "$2" "$out"
}
cnf() {    # cnf <name> <expected stdout> <dimacs input>
  local f out; f=$(mktemp); printf '%s' "$3" > "$f"
  out=$(timeout 120 "$Z" -dimacs "$f" 2>&1); rm -f "$f"
  check "$1" "$2" "$out"
}

smt int-sat $'sat\n((x 4))' '(declare-const x Int)(assert (and (> x 3) (< x 5)))(check-sat)(get-value (x))'
smt int-unsat 'unsat' '(declare-const x Int)(assert (and (> x 5) (< x 3)))(check-sat)'
smt bool-unsat 'unsat' '(declare-const p Bool)(assert p)(assert (not p))(check-sat)'
smt simplify-arith '15' '(simplify (+ 1 2 (* 3 4)))'
smt simplify-bv '#x10' '(simplify (bvadd #x0f #x01))'
smt define-fun '144' '(define-fun f ((x Int)) Int (* x x))(simplify (f 12))'
smt strings $'sat\n(((str.len s) 4)\n (s "abcd"))' '(declare-const s String)(assert (= s (str.++ "ab" "cd")))(check-sat)(get-value ((str.len s) s))'
smt bv-mul $'sat\n((a #x05))' '(declare-const a (_ BitVec 8))(assert (= (bvmul a #x03) #x0f))(assert (bvult a #x40))(check-sat)(get-value (a))'
smt real-sqrt $'sat\n((x 2.0))' '(declare-const x Real)(assert (= (* x x) 4.0))(assert (> x 0.0))(check-sat)(get-value (x))'
smt optimize-max $'sat\n(objectives\n ((* 3 x) 30)\n)' '(declare-const x Int)(assert (<= 0 x 10))(maximize (* 3 x))(check-sat)(get-objectives)'
smt unsat-core $'unsat\n(a1 a2)' '(set-option :produce-unsat-cores true)(declare-const p Bool)(declare-const q Bool)(assert (! p :named a1))(assert (! (not p) :named a2))(assert (! q :named a3))(check-sat)(get-unsat-core)'
cnf dimacs-unsat 's UNSATISFIABLE' $'p cnf 2 4\n1 2 0\n-1 2 0\n1 -2 0\n-1 -2 0\n'
cnf dimacs-sat $'s SATISFIABLE\nv 1 -2 0' $'p cnf 2 2\n1 0\n-2 0\n'

emit_ctrf "z3-smt2-kat" "$passed" "$failed"
