// Feeds the input to Z3's SMT-LIB2 command interpreter (parse + every command, including check-sat,
// get-model, optimize, Horn/datalog and proof commands), the same front end the `z3` binary uses.
#include "z3_fuzz_common.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > kMaxInput) return -1;
    std::string input(reinterpret_cast<const char *>(data), size);
    if (touches_files(input)) return -1;
    Z3_context ctx = make_context();
    Z3_string out = Z3_eval_smtlib2_string(ctx, input.c_str());
    bool parse_failed = Z3_get_error_code(ctx) != Z3_OK;
    (void)out;
    Z3_del_context(ctx);
    return parse_failed ? -1 : 0;
}
