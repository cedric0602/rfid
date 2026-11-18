#!/usr/bin/env bash
# A lancer depuis le master apres avoir redemarre la VM.
# Les DaemonSets (xmrig, node-exporter) reviennent seuls ; ce script remet
# simplement le noeud en etat "schedulable".
set -euo pipefail

NODE="${NODE:-vmubuntu}"
KUBECTL="microk8s kubectl"

echo ">> Attente que ${NODE} soit Ready (max 5 min)"
$KUBECTL wait --for=condition=Ready "node/${NODE}" --timeout=300s

echo ">> Uncordon de ${NODE}"
$KUBECTL uncordon "${NODE}"

$KUBECTL get nodes -o wide
