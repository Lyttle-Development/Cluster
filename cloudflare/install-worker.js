/**
 * Cloudflare Worker: install.cluster.lyttle.dev
 *
 * Handles requests to https://install.cluster.lyttle.dev:
 * - If accessed via curl or wget: streams the raw bootstrap.sh script directly.
 * - If accessed via web browser: redirects the user to the GitHub repository.
 */

export default {
  async fetch(request) {
    const userAgent = (request.headers.get("user-agent") || "").toLowerCase();
    const isCli = userAgent.includes("curl") || userAgent.includes("wget");

    const githubRawUrl =
      "https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh";
    const repoUrl = "https://github.com/Lyttle-Development/Cluster";

    // Browser navigation redirect
    if (!isCli) {
      return Response.redirect(repoUrl, 302);
    }

    // Direct script streaming for terminal clients
    try {
      const response = await fetch(githubRawUrl);
      if (!response.ok) {
        return new Response(
          `# Error fetching installer from GitHub (${response.status})\n`,
          {
            status: response.status,
            headers: { "content-type": "text/plain; charset=utf-8" },
          }
        );
      }

      return new Response(response.body, {
        status: 200,
        headers: {
          "content-type": "text/plain; charset=utf-8",
          "cache-control": "public, max-age=300",
        },
      });
    } catch (err) {
      return new Response(`# Installer fetch failed: ${err.message}\n`, {
        status: 502,
        headers: { "content-type": "text/plain; charset=utf-8" },
      });
    }
  },
};
