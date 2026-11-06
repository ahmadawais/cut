#pragma once
/// Puts this process in the given seatbelt profile (see `man sandbox_init`). Returns 0 on success; on failure,
/// writes a message to `error` (free it with cut_sandbox_free_error).
int cut_sandbox_apply(const char *profile, char **error);
void cut_sandbox_free_error(char *error);
