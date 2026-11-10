// libathena_engine.so is kneejerk's C API (include/systemone.h) and nothing else. The linker takes
// only referenced objects from static libraries, so this table pulls the API in; exports.map exports it.
#include "systemone.h"

__attribute__((used)) static const void * const athena_engine_api[] = {
    (const void *) systemone_load,
    (const void *) systemone_free,
    (const void *) systemone_decide,
    (const void *) systemone_free_string,
    (const void *) systemone_model_type,
};
