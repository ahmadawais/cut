#include "CNoNetwork.h"
#include <sandbox.h>

// sandbox_init is deprecated in the SDK header but supported: it's how Safari's and Chrome's helper processes
// sandbox themselves, and the App Sandbox can't be used here (it blocks the Accessibility API).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
int cut_sandbox_apply(const char *profile, char **error) { return sandbox_init(profile, 0, error); }
void cut_sandbox_free_error(char *error) { sandbox_free_error(error); }
#pragma clang diagnostic pop
