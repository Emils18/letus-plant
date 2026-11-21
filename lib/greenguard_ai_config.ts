/** The single Web runtime configuration point for GreenGuard inference. */
const DEFAULT_GREENGUARD_AI_URL = "http://185.133.48.73";

export function getGreenGuardAiBaseUrl(): string {
  return (
    process.env.GREENGUARD_AI_URL?.trim() || DEFAULT_GREENGUARD_AI_URL
  ).replace(/\/+$/, "");
}
