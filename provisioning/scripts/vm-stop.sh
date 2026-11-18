#!/usr/bin/env bash
# Arret propre de la VM worker (a lancer depuis le master).
# Usage : ./vm-stop.sh        (variables surchargeables : NODE, NODE_IP, SSH_USER)
set -euo pipefail

NODE="${NODE:-vmubuntu}"
NODE_IP="${NODE_IP:-192.168.0.52}"
SSH_USER="${SSH_USER:-cedric}"
KUBECTL="microk8s kubectl"

echo ">> Cordon + drain de ${NODE}"
$KUBECTL cordon "${NODE}"
$KUBECTL drain "${NODE}" --ignore-daemonsets --delete-emptydir-data --timeout=120s

echo ">> Arret de la VM ${NODE_IP}"
ssh -t "${SSH_USER}@${NODE_IP}" 'sudo shutdown -h now' || true

echo ">> Termine. Pense a lancer vm-start.sh apres le redemarrage de la VM."

