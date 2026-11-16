#!/usr/bin/env bash
# Irreversibly wipe every chart/image on the zot OCI registry.
#
# zot's image has no shell, so this scales zot to 0, mounts zot-pvc from a
# temp busybox pod on the same node to delete the data, then scales zot
# back up. Invoke via `just zot-wipe` (sets KUBECONFIG for you).
set -euo pipefail

read -rp "This deletes ALL repositories on zot.nicklab.org permanently. Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

kubectl scale deployment/zot -n zot --replicas=0
kubectl wait --for=delete pod -l app=zot -n zot --timeout=60s || true

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: zot-wipe-helper
  namespace: zot
spec:
  nodeSelector:
    kubernetes.io/hostname: old-white-worker
  restartPolicy: Never
  containers:
    - name: wipe
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: zot-volume
          mountPath: /var/lib/registry
  volumes:
    - name: zot-volume
      persistentVolumeClaim:
        claimName: zot-pvc
EOF

kubectl wait --for=condition=Ready pod/zot-wipe-helper -n zot --timeout=60s
kubectl exec -n zot zot-wipe-helper -- sh -c 'find /var/lib/registry -mindepth 1 -delete'
kubectl delete pod zot-wipe-helper -n zot --wait=true

kubectl scale deployment/zot -n zot --replicas=1
kubectl rollout status deployment/zot -n zot --timeout=60s

echo "zot wiped. Catalog now:"
for i in 1 2 3 4 5; do
    out=$(curl -s https://zot.nicklab.org/v2/_catalog)
    if [ -n "$out" ] && [ "$out" != "no available server" ]; then
        echo "$out"
        exit 0
    fi
    sleep 2
done
echo "$out (tunnel/ingress still catching up after rollout — re-run: curl -s https://zot.nicklab.org/v2/_catalog)"
