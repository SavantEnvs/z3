// Shared helpers for the Z3 C-API fuzz harnesses (header-only; each harness is its own TU).
#pragma once
#include <z3.h>
#include <cstddef>
#include <cstdint>
#include <string>

// Per-check deterministic resource limit (Z3 "rlimit" units), NOT a wall-clock timer.
static const char *const kRlimit = "2000000";
// Hard cap on Z3's own allocation accounting (MB): out-of-memory becomes a Z3 error, not a kill.
static const char *const kMemoryMaxMB = "768";
static const size_t kMaxInput = 1u << 15;

static void ignore_z3_error(Z3_context, Z3_error_code) {}

// Z3 option/command names that make Z3 open a caller-chosen file (output channels, proof/drat/trace
// logs, dumps, includes). The harness never lets fuzzer bytes pick a path to write.
static bool touches_files(const std::string &s) {
    static const char *const bad[] = {"channel", "file",  ".log",   "_log",  "-log",
                                      "log_",    "dump",  "trace",  "include", "drat", "read-"};
    for (const char *b : bad)
        if (s.find(b) != std::string::npos) return true;
    return false;
}

static void init_z3_globals() {
    static bool done = false;
    if (done) return;
    done = true;
    Z3_global_param_set("rlimit", kRlimit);
    Z3_global_param_set("memory_max_size", kMemoryMaxMB);
}

static Z3_context make_context() {
    init_z3_globals();
    Z3_config cfg = Z3_mk_config();
    Z3_context ctx = Z3_mk_context(cfg);
    Z3_del_config(cfg);
    Z3_set_error_handler(ctx, ignore_z3_error);
    return ctx;
}
