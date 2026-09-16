#include <sys/param.h>
// Upstream amalgamation uses intentional SQLite integer narrowing. Keep app warnings enabled.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include "sqlcipher.inc"
#pragma clang diagnostic pop
