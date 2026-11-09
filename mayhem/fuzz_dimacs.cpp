// DIMACS CNF reader (Z3_solver_from_string dispatches on the "p cnf" header) -> SMT solver -> check.
#include "z3_fuzz_common.h"
#include <cstring>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 6 || size > kMaxInput) return -1;
    std::string input(reinterpret_cast<const char *>(data), size);
    if (std::strncmp(input.c_str(), "p cnf", 5) != 0) return -1;
    Z3_context ctx = make_context();
    Z3_solver s = Z3_mk_solver(ctx);
    Z3_solver_inc_ref(ctx, s);
    Z3_solver_from_string(ctx, s, input.c_str());
    if (Z3_get_error_code(ctx) != Z3_OK) {
        Z3_solver_dec_ref(ctx, s);
        Z3_del_context(ctx);
        return -1;
    }
    Z3_lbool r = Z3_solver_check(ctx, s);
    if (r == Z3_L_TRUE) {
        Z3_model m = Z3_solver_get_model(ctx, s);
        if (m) {
            Z3_model_inc_ref(ctx, m);
            (void)Z3_model_to_string(ctx, m);
            Z3_model_dec_ref(ctx, m);
        }
    }
    Z3_solver_dec_ref(ctx, s);
    Z3_del_context(ctx);
    return 0;
}
