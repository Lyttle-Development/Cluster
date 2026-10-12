# Cloudflare Configuration Guide: `install.cluster.lyttle.dev`

This guide explains how to configure Cloudflare DNS and routing for `install.cluster.lyttle.dev` so that anyone (or your bootstrap automations) can run:

```bash
curl -fsSL https://install.cluster.lyttle.dev | sudo bash
```

---

## Architecture of the Install Endpoint

```
  curl -fsSL https://install.cluster.lyttle.dev
                     │
                     ▼
             [ Cloudflare Edge ]
         (SSL Termination & Routing)
                     │
         ┌───────────┴───────────┐
         │                       │
      Option A                Option B
  (Redirect Rule)        (Cloudflare Worker)
         │                       │
         ▼                       ▼
  302 Redirect to        Direct HTTP Stream /
  raw.githubusercontent  Browser Landing Page
```

---

## Option A: Cloudflare Redirect Rule (Recommended - 2 Minutes, Zero Code)

This is the simplest, maintenance-free approach. Cloudflare handles the SSL certificate and redirects `curl` to the raw GitHub script.

### Step 1: Add DNS Record in Cloudflare
1. Go to your **Cloudflare Dashboard** -> Select **`lyttle.dev`**.
2. Navigate to **DNS** -> **Records** -> Click **Add record**.
3. Fill in the following:
   - **Type**: `CNAME`
   - **Name**: `install.cluster` (this resolves to `install.cluster.lyttle.dev`)
   - **Target**: `raw.githubusercontent.com` (or dummy IP `192.0.2.1` / `100::` if using A/AAAA)
   - **Proxy status**: **Proxied** (🟠 Orange cloud must be ENABLED)
   - **TTL**: Auto
4. Click **Save**.

### Step 2: Create a Redirect Rule
1. In Cloudflare, navigate to **Rules** -> **Redirect Rules** -> Click **Create rule**.
2. **Rule name**: `Cluster Install Redirect`
3. Under **If incoming requests match...**:
   - Field: `Hostname`
   - Operator: `equals`
   - Value: `install.cluster.lyttle.dev`
4. Under **Then... (URL Redirect)**:
   - Type: `Dynamic` or `Static`
   - Target URL:
     ```text
     https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh
     ```
   - Status code: `302` (Temporary Redirect) or `301`
   - Preserve query string: Checked (enabled)
5. Click **Deploy**.

> [!NOTE]
> Because `curl` is run with the `-L` flag (`curl -fsSL`), it automatically follows the Cloudflare redirect and streams the script directly into `bash`.

---

## Option B: Cloudflare Worker (Direct Streaming & Browser Friendly)

If you prefer `curl https://install.cluster.lyttle.dev` to return the script directly without an HTTP 302 redirect, and redirect human visitors visiting via a web browser to the GitHub repository, deploy a Cloudflare Worker.

The worker script is provided in this repository at [`cloudflare/install-worker.js`](file:///Users/kiliandebock/Documents/GitHub/Cluster/cloudflare/install-worker.js).

### Step 1: Create the Worker
1. In Cloudflare Dashboard, go to **Workers & Pages** -> **Overview** -> Click **Create application** -> **Create Worker**.
2. Name it `cluster-install`.
3. Click **Deploy**.
4. Click **Edit code** and replace the contents with:
   ```javascript
   export default {
     async fetch(request) {
       const userAgent = request.headers.get("user-agent") || "";
       const isCli = userAgent.includes("curl") || userAgent.includes("Wget");
       const githubRawUrl = "https://raw.githubusercontent.com/Lyttle-Development/Cluster/main/scripts/bootstrap.sh";
       const repoUrl = "https://github.com/Lyttle-Development/Cluster";

       // If accessed via a browser, redirect to the GitHub repository
       if (!isCli) {
         return Response.redirect(repoUrl, 302);
       }

       // If accessed via curl or wget, stream the raw bash script directly
       const response = await fetch(githubRawUrl);
       return new Response(response.body, {
         status: response.status,
         headers: {
           "content-type": "text/plain; charset=utf-8",
           "cache-control": "public, max-age=300",
         },
       });
     },
   };
   ```
5. Click **Deploy**.

### Step 2: Route the Custom Domain to the Worker
1. In the Worker settings, navigate to **Settings** -> **Domains & Routes** -> Click **Add** -> **Custom Domain**.
2. Enter: `install.cluster.lyttle.dev`.
3. Cloudflare will automatically create and manage the necessary DNS records and TLS certificates for `install.cluster.lyttle.dev`.

---

## Verification Test

Once configured, verify from your local terminal:

> 📍 **Run on: Developer PC / Workstation**
```bash
# Test with curl (should output the top lines of bootstrap.sh)
curl -fsSL https://install.cluster.lyttle.dev | head -n 10
```


Expected output:
```text
#!/usr/bin/env bash
# ==============================================================================
# Cluster Bootstrap Orchestrator (One-Liner Entrypoint)
# Repository: https://github.com/Lyttle-Development/Cluster
# ==============================================================================
```
