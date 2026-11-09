// SMT-LIB2 optimization problems (assert-soft / minimize / maximize) through the Optimize API.
#include "z3_fuzz_common.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > kMaxInput) return -1;
    std::string input(reinterpret_cast<const char *>(data), size);
    if (touches_files(input)) return -1;
    Z3_context ctx = make_context();
    Z3_optimize o = Z3_mk_optimize(ctx);
    Z3_optimize_inc_ref(ctx, o);
    Z3_optimize_from_string(ctx, o, input.c_str());
    if (Z3_get_error_code(ctx) != Z3_OK) {
        Z3_optimize_dec_ref(ctx, o);
        Z3_del_context(ctx);
        return -1;
    }
    Z3_lbool r = Z3_optimize_check(ctx, o, 0, nullptr);
    if (r != Z3_L_FALSE) {
        Z3_model m = Z3_optimize_get_model(ctx, o);
        if (m) {
            Z3_model_inc_ref(ctx, m);
            (void)Z3_model_to_string(ctx, m);
            Z3_model_dec_ref(ctx, m);
        }
    }
    Z3_optimize_dec_ref(ctx, o);
    Z3_del_context(ctx);
    return 0;
}
