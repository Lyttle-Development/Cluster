# Application Specification & Golden Standard for AI Agents

> **System Prompt / Instruction Guide for AI Agents**  
> Feed this document to your AI coding agents when prompting them to generate application deployment manifests for your private NAS repository (`/Volumes/NAS/cluster-apps/<app-name>/app.yaml`).

---

## 🎯 Objective for the Agent

Generate a single, self-contained, production-ready Kubernetes manifest (`app.yaml`) that can be applied directly to the Lyttle Cluster using:
```bash
kubectl apply -f app.yaml
# or streamed from NAS:
./scripts/deploy-from-nas.sh --source /Volumes/NAS/cluster-apps/<app-name> --server <SERVER_IP>
```

---

## 🏛️ Cluster Architecture Rules (Mandatory)

1. **Ingress Controller**:
   - The cluster uses **Traefik** as its native ingress controller.
   - Every Ingress resource **must** include the annotation:
     ```yaml
     metadata:
       annotations:
         kubernetes.io/ingress.class: "traefik"
     ```
   - Public traffic reaches the cluster through a Cloudflare Tunnel routed to Traefik.
   - Domain format: `<subdomain>.cluster.lyttle.dev` or custom domain.

2. **Service Type**:
   - Services **must always** be of type `ClusterIP` (default).
   - **Never** use `NodePort` or `LoadBalancer` (there are no open public ports on the VPS).

3. **Database & Persistence Philosophy**:
   - **Do not spin up local stateful database pods (Postgres/MySQL) inside the cluster**.
   - All relational application state lives in the managed **DigitalOcean PostgreSQL 18** cluster.
   - Database connection strings must include `?sslmode=require`.
   - File uploads and media must be stored in S3-compatible object storage (Cloudflare R2, DO Spaces, AWS S3).
   - Ephemeral scratch space or caches can use `emptyDir: {}` or `storageClassName: local-path`.

4. **Security Hardening (Least Privilege)**:
   - Containers should run as non-root users whenever supported by the image.
   - Always set `allowPrivilegeEscalation: false`.
   - Always specify resource `requests` and `limits` to prevent noisy neighbors and OOM kills.

---

## 📋 Standard Resource Bundle Structure

Every application manifest must be bundled in a single `app.yaml` file (separated by `---`) containing the following resources in order:

1. **`Namespace`**: Dedicated namespace for the application.
2. **`Secret`**: Sensitive environment variables (DB URLs, API keys, passwords).
3. **`ConfigMap`**: Non-sensitive environment variables and configuration files.
4. **`Deployment`**: Pod replicas, container spec, health probes, and resource bounds.
5. **`Service`**: Internal cluster networking exposing the pod port.
6. **`Ingress`**: Public HTTP routing through Traefik.

---

## 🌟 Golden Standard Template (`app.yaml`)

AI Agents should use and adapt the following template:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
---
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: my-app
type: Opaque
stringData:
  # Database connection string to Managed DO PostgreSQL 18
  DATABASE_URL: "postgres://db_user:secret_password@db-postgresql-nyc1-do-user-123.b.db.ondigitalocean.com:25060/my_app_db?sslmode=require"
  API_SECRET_KEY: "change-me-to-a-secure-random-string"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: my-app
data:
  NODE_ENV: "production"
  PORT: "3000"
  LOG_LEVEL: "info"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
  labels:
    app.kubernetes.io/name: my-app
spec:
  replicas: 1
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: my-app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: my-app
    spec:
      containers:
      - name: my-app
        image: ghcr.io/org/my-app:v1.0.0
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
          name: http
          protocol: TCP
        envFrom:
        - configMapRef:
            name: my-app-config
        - secretRef:
            name: my-app-secrets
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 512Mi
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 15
          periodSeconds: 20
          timeoutSeconds: 3
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 2
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app
  labels:
    app.kubernetes.io/name: my-app
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: my-app
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
  labels:
    app.kubernetes.io/name: my-app
  annotations:
    kubernetes.io/ingress.class: "traefik"
spec:
  rules:
  - host: my-app.cluster.lyttle.dev
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              name: http
```

---

## 🚫 Common Anti-Patterns (Do NOT Do This)

| Anti-Pattern | Why it breaks the cluster | Correct Approach |
| :--- | :--- | :--- |
| `type: LoadBalancer` or `NodePort` | No public ports are open on the VPS firewall (UFW drops all inbound). | Use `type: ClusterIP` and an `Ingress`. |
| Missing `ingress.class: "traefik"` | Traefik will ignore the Ingress rule and the domain will return HTTP 404. | Always add the `kubernetes.io/ingress.class: "traefik"` annotation. |
| In-cluster PostgreSQL container | Coupled storage; wiping nodes loses database data. | Point app to Managed DigitalOcean PostgreSQL 18 via `DATABASE_URL`. |
| `hostPath` storage volume | Breaks pod scheduling across nodes and leaves data behind on node wipes. | Use S3/R2 for files, DO Postgres for data, or `emptyDir` for scratch. |
| `privileged: true` | Massive security hole; allows container breakout to host VPS. | Keep `privileged: false`, `allowPrivilegeEscalation: false`, drop all caps. |

---

## ✅ Quality Checklist for Agents

Before outputting the manifest, ensure:
- [ ] YAML is valid with proper 2-space indentation.
- [ ] All 6 resources share the identical `namespace`.
- [ ] Service `targetPort` matches Deployment `containerPort` (by number or name).
- [ ] Ingress `backend.service.name` matches Service `metadata.name`.
- [ ] Ingress has `kubernetes.io/ingress.class: "traefik"` annotation.
- [ ] Health check probe paths (`/health`, `/healthz`, `/`, etc.) are realistic for the image.
- [ ] Resource requests and limits are explicitly defined.
