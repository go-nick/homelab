# homelab

Personal Kubernetes homelab — self-hosted services, monitoring, and ingress, all managed through GitOps.

## Hardware

2-node k3s cluster on NixOS-managed bare metal — see [nixos-flake](../nixos/flake) for OS-layer config and full hardware details.

- **beelink-master** — control plane, monitoring stack (Grafana, Prometheus)
- **old-white-worker** — worker node, media services

## GitOps Architecture

This repo is the single source of truth for the cluster, reconciled continuously by FluxCD.

Every app and infrastructure component is defined once and deployed through a base → staging overlay structure (Kustomize) — the same dev → staging → production promotion shape I run professionally for Rancher's Helm chart release pipeline: validate on staging, promote via pull request, nothing deployed by hand.

Flux watches this repo and reconciles cluster state automatically.

## What's Running

**Apps**
- AdGuard Home — network-wide DNS ad-blocking
- Homarr — unified dashboard for the homelab
- Linkding — self-hosted bookmark manager
- Mealie — recipe manager
- Plex — media server
- rrstack — media library automation

**Infrastructure**
- Cloudflare Tunnel — secure ingress without exposed ports, host-allowlisted, CSRF-hardened

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
│   │   ├── mealie/
│   │   ├── plex/
│   │   └── rrstack/
│   └── staging/                # staging overlay, promotes to cluster
├── infrastructure/
│   ├── base/cloudflared/       # tunnel + ingress
│   └── staging/
├── monitoring/
│   ├── controllers/            # kube-prometheus-stack
│   └── configs/
└── tests/                      # validation before promotion
```

## Design Patterns

All ports must be named following the pattern: 
```
s-p-<app> # service port names
c-p-<app> # container port names
```

