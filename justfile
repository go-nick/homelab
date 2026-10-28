# Every recipe runs against the homelab cluster, never whatever KUBECONFIG
# happens to be set to in the calling shell.
export KUBECONFIG := env_var('HOME') / ".kube/homelab.yaml"

KUSTOMIZATIONS := "apps flux-system infrastructure monitoring monitoring-configs"

default:
    @just --list

# Show READY/SUSPENDED/REVISION status of every Flux Kustomization
kustomizations:
    flux get kustomizations -A

# Force an immediate reconcile of all 5 root Kustomizations
reconcile:
    flux reconcile kustomization {{ KUSTOMIZATIONS }}

# Set spec.interval to <hours> on all root Kustomizations (never touches GitRepository polling). e.g. just interval 8
interval hours:
    #!/usr/bin/env bash
    set -euo pipefail
    for pair in clusters/homelab/apps.yaml:apps \
                clusters/homelab/infrastructure.yaml:infrastructure \
                clusters/homelab/monitoring.yaml:monitoring \
                clusters/homelab/flux-system/gotk-sync.yaml:flux-system; do
        file="${pair%%:*}"
        name="${pair##*:}"
        yq eval "(select(.kind == \"Kustomization\" and .metadata.name == \"$name\") | .spec.interval) = \"{{ hours }}h0m0s\"" -i "$file"
        echo "set $file ($name) -> {{ hours }}h0m0s"
    done

# Pause reconciliation so Flux stops reverting/pruning manual kubectl changes. Takes one or more Flux Kustomization names (run `just kustomizations` to see them). e.g. just suspend infrastructure
suspend *kustomizationName:
    flux suspend kustomization {{ kustomizationName }}

# Resume reconciliation suspended with `just suspend`. Takes one or more Flux Kustomization names (run `just kustomizations` to see them). e.g. just resume infrastructure
resume *kustomizationName:
    flux resume kustomization {{ kustomizationName }}

# Render a root Kustomization as Flux would (reads cluster, applies nothing). Takes one Flux Kustomization name (run `just kustomizations` to see them): apps|infrastructure|monitoring|monitoring-configs|flux-system
build kustomizationName:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ kustomizationName }}" in
        apps) path=apps/staging; file=clusters/homelab/apps.yaml; ignore="" ;;
        infrastructure) path=infrastructure/staging; file=clusters/homelab/infrastructure.yaml; ignore="" ;;
        monitoring) path=monitoring/controllers/staging; file=clusters/homelab/monitoring.yaml; ignore="" ;;
        monitoring-configs) path=monitoring/configs/staging; file=clusters/homelab/monitoring.yaml; ignore="" ;;
        flux-system) path=clusters/homelab; file=clusters/homelab/flux-system/gotk-sync.yaml; ignore=".sops.yaml" ;;
        *) echo "Unknown kustomization: {{ kustomizationName }} (run 'just kustomizations' to see valid names)" >&2; exit 1 ;;
    esac
    if [ -n "$ignore" ]; then
        flux build kustomization "{{ kustomizationName }}" --path "$path" --kustomization-file "$file" --ignore-paths "$ignore"
    else
        flux build kustomization "{{ kustomizationName }}" --path "$path" --kustomization-file "$file"
    fi

# Plain `kustomize build` on a leaf path with its own kustomization.yaml, fully offline. Find candidate paths with: find . -name kustomization.yaml -not -path './clusters/*'. e.g. just kbuild infrastructure/base/cert-manager
kbuild path:
    kustomize build {{ path }}

