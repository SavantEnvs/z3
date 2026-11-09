// First input byte selects a goal-transforming tactic; the rest is SMT-LIB2 whose assertions become
// the goal. Solving tactics (smt/sat/nlsat/qf*) are left to fuzz_smt2_eval, where Z3's rlimit bounds them.
#include "z3_fuzz_common.h"

static const char *const kTactics[] = {
    "simplify",        "propagate-values", "solve-eqs",         "elim-uncnstr",      "ctx-simplify",
    "elim-term-ite",   "bit-blast",        "blast-term-ite",    "aig",               "card2bv",
    "cofactor-term-ite","der",             "dom-simplify",      "elim-predicates",   "flatten",
    "lia2card",        "lia2pb",           "macro-finder",      "max-bv-sharing",    "nnf",
    "normalize-bounds","occf",             "pb2bv",             "propagate-bv-bounds","propagate-ineqs",
    "purify-arith",    "reduce-args",      "reduce-invertible", "snf",               "tseitin-cnf",
    "tseitin-cnf-core","ufbv-rewriter",    "distribute-forall", "ackermannize_bv",   "elim-and",
    "nla2bv",          "qe-light",         "special-relations", "injectivity",       "eq2bv",
};

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 2 || size > kMaxInput) return -1;
    const char *name = kTactics[data[0] % (sizeof(kTactics) / sizeof(kTactics[0]))];
    std::string input(reinterpret_cast<const char *>(data + 1), size - 1);
    if (touches_files(input)) return -1;
    Z3_context ctx = make_context();
    Z3_ast_vector v = Z3_parse_smtlib2_string(ctx, input.c_str(), 0, nullptr, nullptr, 0, nullptr, nullptr);
    if (Z3_get_error_code(ctx) != Z3_OK || !v) {
        Z3_del_context(ctx);
        return -1;
    }
    Z3_ast_vector_inc_ref(ctx, v);
    Z3_tactic t = Z3_mk_tactic(ctx, name);
    if (Z3_get_error_code(ctx) != Z3_OK || !t) {
        Z3_ast_vector_dec_ref(ctx, v);
        Z3_del_context(ctx);
        return -1;
    }
    Z3_tactic_inc_ref(ctx, t);
    Z3_goal g = Z3_mk_goal(ctx, true, true, false);
    Z3_goal_inc_ref(ctx, g);
    unsigned n = Z3_ast_vector_size(ctx, v);
    for (unsigned i = 0; i < n; ++i) Z3_goal_assert(ctx, g, Z3_ast_vector_get(ctx, v, i));
    Z3_apply_result r = Z3_tactic_apply(ctx, t, g);
    if (r && Z3_get_error_code(ctx) == Z3_OK) {
        Z3_apply_result_inc_ref(ctx, r);
        unsigned k = Z3_apply_result_get_num_subgoals(ctx, r);
        for (unsigned i = 0; i < k; ++i) {
            Z3_goal sg = Z3_apply_result_get_subgoal(ctx, r, i);
            Z3_goal_inc_ref(ctx, sg);
            (void)Z3_goal_to_string(ctx, sg);
            Z3_goal_dec_ref(ctx, sg);
        }
        Z3_apply_result_dec_ref(ctx, r);
    }
    Z3_goal_dec_ref(ctx, g);
    Z3_tactic_dec_ref(ctx, t);
    Z3_ast_vector_dec_ref(ctx, v);
    Z3_del_context(ctx);
    return 0;
}
