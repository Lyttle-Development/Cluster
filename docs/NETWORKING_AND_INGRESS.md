# Networking & Ingress Architecture

This guide explains how traffic flows securely from the internet to your services without exposing ports on your VPS instances, and how internal pods communicate over an encrypted overlay.

---

## 1. Zero-Trust Public Ingress (Cloudflare Tunnel)

### The Problem with Traditional Ingress
In traditional VPS setups, ports `80` and `443` are opened to `0.0.0.0/0`. This exposes the server to:
- Direct IP port scans (e.g. automated scanners crawling all OVH IP ranges).
- Layer 3/4 and Layer 7 volumetric DDoS attacks hitting your VPS bandwidth.
- Unpatched CVEs in the web server / TLS termination proxy.
- Direct-to-origin bypasses (attackers bypassing Cloudflare by sending requests directly to the VPS IP).

### The Cloudflare Tunnel Solution
With **Cloudflare Tunnels (`cloudflared`)**:
```
User Request
     │
     ▼
[ Cloudflare Edge ] (WAF, DDoS Protection, SSL Termination)
     │
     ▼ (Outbound QUIC / HTTP2 Tunnel over TLS)
[ VPS Firewall (UFW) ] ---> Blocks ALL inbound traffic on 80, 443, 6443
     │
     ▼ (Tunnel Agent in Cluster)
[ cloudflared Pod ]
     │
     ▼ (Cluster Internal HTTP)
[ Traefik Ingress Controller ]
     │
     ▼ (Internal Service Routing)
[ Application Pods ]
```

### Key Advantages:
1. **Zero Open Ports**: The VPS firewall drops all unsolicited inbound packets.
2. **Built-in DDoS & WAF**: Attack traffic is absorbed at Cloudflare's global edge network.
3. **No Dynamic DNS Hassles**: The tunnel agent identifies itself to Cloudflare via token; IP changes on the VPS never break ingress.
4. **SSL Managed at Edge**: Cloudflare manages client-facing SSL certificates automatically.

---

## 2. Pod-to-Pod Overlay Networking (WireGuard)

Within the cluster, nodes can be located in the same or different OVH datacenters.

- K3s is configured with:
  ```bash
  --flannel-backend=wireguard-native
  ```
- **In-Kernel Performance**: WireGuard runs inside the Linux kernel on Debian 13, maximizing throughput and minimizing CPU usage.
- **End-to-End Encryption**: Every packet between nodes is cryptographically authenticated and encrypted with ChaCha20-Poly1305.

---

## 3. Host Firewall Policy (UFW)

The firewall script (`02-firewall-hardening.sh`) sets up the following strict policy:

| Direction | Port / Protocol | Source | Purpose |
| :--- | :--- | :--- | :--- |
| **Incoming** | Default `DROP` | Any | Block all unsolicited internet traffic |
| **Incoming** | `22/tcp` (or custom SSH) | Management IP / WireGuard | Remote server administration |
| **Incoming** | `51820/udp` | Cluster Node IPs | Flannel WireGuard encrypted overlay |
| **Incoming** | `6443/tcp` | Cluster Node IPs | K3s API server communication between nodes |
| **Outgoing** | Default `ALLOW` | Any | Cloudflare tunnels, outbound PostgreSQL, package updates |
| **Loopback / Flannel** | `lo`, `cni0`, `flannel.1` | Local | Allow internal container networking |
