/** @param {NodeJS.ProcessEnv} env */
export function deploymentBasePath(env = process.env) {
  const explicitBasePath = normalizeBasePath(env.BASE_PATH ?? "");
  if (explicitBasePath) return explicitBasePath;

  if (env.GITHUB_PAGES !== "true") return "";

  const repositoryName = env.GITHUB_REPOSITORY?.split("/").at(-1);
  if (!repositoryName || repositoryName.endsWith(".github.io")) return "";

  return `/${repositoryName}`;
}

/** @param {string} basePath */
function normalizeBasePath(basePath) {
  const normalized = basePath.trim().replace(/^\/+|\/+$/g, "");
  return normalized ? `/${normalized}` : "";
}
