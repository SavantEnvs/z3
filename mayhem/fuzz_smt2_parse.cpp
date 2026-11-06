// SMT-LIB2 parser -> AST -> simplifier -> printer -> re-parse round trip (no solving).
#include "z3_fuzz_common.h"
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > kMaxInput) return -1;
    std::string input(reinterpret_cast<const char *>(data), size);
    if (touches_files(input)) return -1;
    Z3_context ctx = make_context();
    Z3_ast_vector v = Z3_parse_smtlib2_string(ctx, input.c_str(), 0, nullptr, nullptr, 0, nullptr, nullptr);
    if (Z3_get_error_code(ctx) != Z3_OK || !v) {
        Z3_del_context(ctx);
        return -1;
    }
    Z3_ast_vector_inc_ref(ctx, v);
    unsigned n = Z3_ast_vector_size(ctx, v);
    std::vector<Z3_ast> asserts;
    for (unsigned i = 0; i < n; ++i) {
        Z3_ast a = Z3_ast_vector_get(ctx, v, i);
        asserts.push_back(a);
        Z3_ast s = Z3_simplify(ctx, a);
        if (s) (void)Z3_ast_to_string(ctx, s);
    }
    if (n > 0) {
        Z3_string text = Z3_benchmark_to_smtlib_string(ctx, "fuzz", "", "unknown", "", n - 1, asserts.data(),
                                                       asserts[n - 1]);
        if (text && Z3_get_error_code(ctx) == Z3_OK) {
            std::string again(text);
            Z3_ast_vector w = Z3_parse_smtlib2_string(ctx, again.c_str(), 0, nullptr, nullptr, 0, nullptr, nullptr);
            if (w) {
                Z3_ast_vector_inc_ref(ctx, w);
                Z3_ast_vector_dec_ref(ctx, w);
            }
        }
    }
    Z3_ast_vector_dec_ref(ctx, v);
    Z3_del_context(ctx);
    return 0;
}
