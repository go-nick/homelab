# homelab

Personal Kubernetes homelab — self-hosted services, monitoring, and ingress, all managed through GitOps.

## Quick-Commands

Common Flux operations are wrapped in a [`justfile`](https://github.com/casey/just) — install `just`, then:

```
just              # list all recipes with descriptions
just kustomizations          # status of every Flux Kustomization
just reconcile                # force an immediate reconcile
just suspend <name>           # pause reconciliation (e.g. while debugging live)
just resume <name>            # resume it
just build <name>             # render a root Kustomization as Flux would, nothing applied
just kbuild <path>            # plain offline `kustomize build` on a leaf path
just interval <hours>         # bulk-set the reconcile interval on all root Kustomizations
just --list                   # same list as bare `just`, with each recipe's parameters and description
just --show <cmd>              # print a recipe's actual source — see exactly what it runs before running it
```

Run `just kustomizations` to find the Kustomization names `suspend`/`resume`/`build` expect.

## Hardware

2-node k3s cluster on NixOS-managed bare metal — see [nixos-flake](../nixos/flake) for OS-layer config and full hardware details.

- **beelink-master** — control plane, monitoring stack (Grafana, Prometheus)
- **old-white-worker** — worker node, media services

## GitOps Architecture

This repo is the single source of truth for the cluster, reconciled continuously by FluxCD.

Every app and infrastructure component is defined once and deployed through a base → staging overlay structure (Kustomize) — the same dev → staging → production promotion shape I run professionally for Rancher's Helm chart release pipeline: validate on staging, promote via pull request, nothing deployed by hand.

Flux watches this repo and reconciles cluster state automatically.

## Design Patterns

All ports must be named following the pattern:
```
s-p-<app> # service port names
c-p-<app> # container port names
```

### TLS: cert-manager + Reflector

One shared `ClusterIssuer` (`letsencrypt-production`, DNS-01 via Cloudflare) issues one `Certificate` in the `cert-manager` namespace, covering every hostname in use. Reflector mirrors that cert's `Secret` into whichever namespaces need it (`reflector.v1.k8s.emberstack.com/*` annotations on the `Certificate`'s `secretTemplate`) — one cert, one renewal, no per-app ACME config, no manually copying secrets around.

Each app's `Ingress`/`HelmRelease` just references the mirrored secret name:
```yaml
tls:
  - secretName: nicklab-org-tls
    hosts:
      - <app>.nicklab.org
```

Gotcha: a wildcard SAN only ever covers its leftmost label. `*.nicklab.org` covers `zot.nicklab.org` fine, but not `local.adguard.nicklab.org` — no wildcard shape reaches a non-leftmost label, on any CA. Resolved by listing each `local.*` hostname as its own exact SAN entry in `certificate.yaml` instead.

### Renovate: automated updates + CI gate

Renovate opens a PR for every dependency bump (chart versions, container image tags, Flux controller images). `renovate.json` splits the risk by update type:

- **major** — never auto-merged, reviewed by hand (a chart's "minor" bump once shipped an app major version underneath — not safe to trust blindly)
- **minor / patch / pin / digest** — auto-merged via GitHub's native PR automerge, but only after CI passes
- flux controller images are grouped into a single PR instead of 4 separate ones

CI (`.github/workflows/validate.yaml`) is the gate that makes auto-merge safe: every PR runs `kustomize build` across every kustomization in the repo, then pipes the output through `kubeconform` (schema-checked against core Kubernetes plus the Flux CRD catalog, so a malformed `HelmRelease`/`OCIRepository`/`Certificate` fails the same as a malformed `Deployment`). `actions/checkout` and the `kustomize`/`kubeconform` binaries are pinned to an exact commit SHA / sha256 checksum, not a floating tag.

`tests/` holds manual Helm values/template scratch files (e.g. `tests/homarr/`, `tests/plex/`) used to sanity-check a chart's rendered output by hand before committing values — separate from the automated CI gate above.

## Homarr — Internal vs External URL

Homarr's status ping runs server-side, from Homarr's own pod — not the browser. `local.<app>.nicklab.org` hostnames only resolve on devices pointed at AdGuard (your LAN), not inside the cluster's own DNS, so pinging that hostname from Homarr's pod shows a false red status even when the app is healthy.

Fix: set each app's **Internal URL** (used for the status ping) to the in-cluster Service address, keep **External URL** as the `local.*.nicklab.org` hostname (used when clicking the tile):

```
http://<service>.<namespace>.svc.cluster.local:<port>
```

e.g. `http://prowlarr.rrstack.svc.cluster.local:9696`

## What's Running

**Apps**
- AdGuard Home — network-wide DNS ad-blocking
- Homarr — unified dashboard for the homelab
- Linkding — self-hosted bookmark manager
- n8n — workflow automation
- Plex — media server
- rrstack — media library automation (Prowlarr, Radarr, Sonarr, SABnzbd)
- Zot — self-hosted OCI/Helm chart registry

**Infrastructure**
- Cloudflare Tunnel — secure ingress without exposed ports, host-allowlisted, CSRF-hardened
- cert-manager — Let's Encrypt certificates via Cloudflare DNS-01, no ports exposed
- Reflector — mirrors the shared TLS secret into every app namespace that needs it
- Renovate — automated dependency updates, gated by CI, auto-merged for minor/patch

**Monitoring**
- kube-prometheus-stack — Prometheus + Grafana, TLS-secured

**Secrets**
- SOPS + age — encrypted in git, decrypted at reconcile time, never committed in plaintext

## Layout

```
homelab/
├── clusters/
│   └── homelab/
│       └── flux-system/        # Flux bootstrap
├── apps/
│   ├── base/                   # app definitions
│   │   ├── adguard/
│   │   ├── homarr/
│   │   ├── linkding/
│   │   ├── n8n/
│   │   ├── plex/
│   │   ├── rrstack/
│   │   └── zot/
│   └── staging/                # staging overlay, promotes to cluster
├── infrastructure/
│   ├── base/
│   │   ├── cert-manager/       # ClusterIssuers + shared wildcard Certificate
│   │   ├── reflector/          # cross-namespace secret mirroring
│   │   ├── renovate/           # dependency update bot
│   │   └── tunnel/             # Cloudflare Tunnel + ingress
│   └── staging/
├── monitoring/
│   ├── controllers/            # kube-prometheus-stack
│   └── configs/
├── justfile                    # Flux helper commands, see Quick-Commands
└── tests/                      # manual helm values/template scratch tests
```
