# Plan: Add Nginx Reverse Proxy for awspx UI

**Status: ON HOLD** — depends on whether Guacamole fix works. If learners use Guacamole, they can access awspx at `http://localhost:10080` inside the desktop session and this plan is unnecessary. If Guacamole doesn't work out, come back to this plan.

## Context

This is a 2-hour AWS IAM security workshop. Learners access their EC2 workstation via browser at a public hostname like `https://cool-phoenix-544.workstations.learn.resilientsecurity.cloud/`.

### Current Instance Architecture

**Nginx** (port 80/443 with SSL) is the front door, already proxying:
- `/` → static HTML (`/usr/share/nginx/html/`)
- `/vnc/` → VNC on `127.0.0.1:6080`
- `/websockify` → WebSocket for VNC on `127.0.0.1:6080`
- `/guacamole` → Apache Guacamole (Tomcat) on `127.0.0.1:8080`

**awspx** Docker container serves its Vue.js UI on `127.0.0.1:10080` (port 80 inside container, mapped to 10080 on host to avoid nginx conflict). Backed by Neo4j on `127.0.0.1:7687`.

**Key files:**
- Nginx config: `/etc/nginx/sites-enabled/default`
- SSL cert: `/etc/lego/certificates/cool-phoenix-544.workstations.learn.resilientsecurity.cloud.crt`
- awspx Docker container: `beatro0t/awspx:latest`, created by `labs/wwhf-setup.sh` Step 4
- Setup script: `labs/wwhf-setup.sh`

### The Problem

Learners currently can't access the awspx graph UI from their browser. awspx only listens on `127.0.0.1:10080`, which isn't reachable from outside the instance. We need nginx to proxy browser traffic to awspx.

---

## Implementation

### Approach: Add `/awspx/` location block to nginx config

Add a reverse proxy location in the nginx SSL server block in `/etc/nginx/sites-enabled/default`.

**Considerations:**
1. awspx is a Vue.js SPA (Cytoscape.js graph on canvas). It may expect to be served at `/`, not `/awspx/`. If the SPA's asset paths are relative, a `proxy_pass` with a trailing slash should handle path rewriting. If it uses absolute paths (e.g., `/js/app.js`), we may need `sub_filter` to rewrite HTML, or configure awspx's Vue base path.
1. awspx uses Neo4j Bolt protocol on port 7687 for graph queries from the browser. The frontend JavaScript connects directly to `bolt://localhost:7687`. This will NOT work from a remote browser — it would try to connect to the learner's localhost, not the EC2 instance. We may need to proxy WebSocket traffic for Bolt as well, or override the Neo4j connection URL in the awspx frontend config.
1. WebSocket support is needed if awspx uses WebSockets (Bolt protocol does).

### Step 1: Investigate awspx frontend behavior

Before writing config, answer these questions:
- Does the awspx SPA use relative or absolute asset paths? Check by curling `http://127.0.0.1:10080/` from the instance and examining the HTML.
- How does the frontend connect to Neo4j? Check the JavaScript for the Bolt connection URL. It's likely hardcoded to `bolt://localhost:7687`.
- Does awspx have any configuration for base URL or Neo4j endpoint?

**Commands to run on the instance:**
```bash
# Check what HTML awspx serves
sudo docker exec awspx curl -s http://localhost:80 | head -50

# Find Neo4j connection config in the frontend JS
sudo docker exec awspx grep -r "bolt://" /opt/awspx/www/ 2>/dev/null
sudo docker exec awspx grep -r "7687" /opt/awspx/www/ 2>/dev/null

# Check if there's a Vue config with publicPath/base
sudo docker exec awspx cat /opt/awspx/www/index.html 2>/dev/null
sudo docker exec awspx ls /opt/awspx/www/js/ 2>/dev/null
```

### Step 2: Add nginx location block

In `/etc/nginx/sites-enabled/default`, inside the `server` block for port 443, add:

```nginx
location /awspx/ {
    proxy_pass http://127.0.0.1:10080/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

**Note:** The trailing `/` on both `location /awspx/` and `proxy_pass .../` is critical — it strips the `/awspx/` prefix before forwarding.

### Step 3: Proxy Neo4j Bolt (likely needed)

The browser-side JS needs to reach Neo4j. Add a Bolt WebSocket proxy:

```nginx
location /bolt/ {
    proxy_pass http://127.0.0.1:7687/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
}
```

Then we'd need to modify the awspx frontend to connect to `wss://HOSTNAME/bolt/` instead of `bolt://localhost:7687`. This may require patching the JS bundle inside the container.

### Step 4: Add nginx config to setup script

Add the nginx config step to `labs/wwhf-setup.sh` — either as part of Step 4 (after container creation) or as a new step. The script should:
1. Write the nginx location blocks to a file like `/etc/nginx/conf.d/awspx.conf` or patch `sites-enabled/default`
1. Test with `sudo nginx -t`
1. Reload with `sudo systemctl reload nginx`

### Step 5: Update lab instructions

Update `labs/lab-1-layin-down-the-law/lab-1-instructions.md` to reference awspx at `https://HOSTNAME/awspx/` instead of `http://localhost`.

---

## Key Risk: Neo4j Bolt Connection

This is the hardest part. The awspx Vue.js frontend connects directly from the browser to Neo4j via the Bolt protocol. When awspx was served on localhost, `bolt://localhost:7687` worked because the browser was on the same machine (via VNC/Guacamole). With a remote browser, this breaks.

**Options:**
1. **Keep using Guacamole/VNC for awspx** — learners open awspx at `http://localhost:10080` inside their Guacamole desktop session. No nginx proxy needed. Simplest but requires learners to use the Guacamole remote desktop.
1. **Proxy everything through nginx** — proxy both the HTTP UI and the Bolt WebSocket, patch the JS to use the proxied Bolt URL. More complex but gives a native browser experience.
1. **Use `--network host`** on the Docker container and open port 10080 in the security group — learners hit `http://HOSTNAME:10080` directly. Requires security group changes and loses SSL.

**Recommendation for tomorrow:** Option 1 (Guacamole) is lowest risk. Option 2 is better UX but needs investigation into the Bolt connection patching.

---

## Verification

1. From learner's local browser, navigate to `https://HOSTNAME/awspx/`
1. Confirm the Vue.js SPA loads (graph canvas renders)
1. Search for an IAM resource and confirm Neo4j queries return data
1. Confirm existing services (`/guacamole`, `/vnc/`) still work
