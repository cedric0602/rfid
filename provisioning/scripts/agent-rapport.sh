#!/usr/bin/env bash
# Agent "rapport du jour" : collecte l'etat du homelab (lecture seule),
# le fait resumer par Claude, puis l'envoie par mail (msmtp).
#
# Config locale (PAS dans git) : ~/.config/agent-rapport.env
#   MAIL_TO=toi@exemple.com
#   CLAUDE_BIN=/home/<user>/.local/bin/claude   (optionnel)
#
# Test sans mail :  DRY_RUN=1 provisioning/scripts/agent-rapport.sh
set -uo pipefail

CONF="${HOME}/.config/agent-rapport.env"
[ -f "$CONF" ] && . "$CONF"

CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"
KUBECTL="microk8s kubectl"
DRY_RUN="${DRY_RUN:-0}"
DATE="$(date '+%A %d %B %Y %H:%M')"

section() { printf '\n===== %s =====\n' "$1"; }
run()     { timeout 30 "$@" 2>&1 || echo "(commande en echec: $*)"; }

collect() {
  section "Date / machine"
  echo "$DATE sur $(hostname)"; uptime

  section "Noeuds"
  run $KUBECTL get nodes -o wide
  run $KUBECTL top nodes

  section "Pods qui ne sont PAS Running/Completed"
  run $KUBECTL get pods -A --no-headers | awk '$4!="Running" && $4!="Completed"' || true

  section "Pods avec redemarrages (top 15)"
  run $KUBECTL get pods -A --no-headers --sort-by='.status.containerStatuses[0].restartCount' \
    | awk '$5+0>0' | tail -15

  section "Tous les pods"
  run $KUBECTL get pods -A -o wide

  section "Deployments / DaemonSets / StatefulSets"
  run $KUBECTL get deploy,ds,sts -A

  section "Evenements Warning (24 dernieres lignes)"
  run $KUBECTL get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -24

  section "Stockage (PVC)"
  run $KUBECTL get pvc -A

  section "Disques du master"
  df -h -x tmpfs -x squashfs -x overlay 2>/dev/null

  section "Montage photos externe (Immich)"
  if mountpoint -q /mnt/photos-externe; then echo "monte"; else echo "NON MONTE"; fi

  section "Memoire / batterie"
  free -h
  cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | sed 's/^/batterie %: /'
  cat /sys/class/power_supply/AC*/online 2>/dev/null | sed 's/^/secteur (1=oui): /'
}

PROMPT="Tu es l'agent de surveillance d'un petit homelab MicroK8s (master = laptop 'csiaoh',
worker = VM 'vmubuntu' qui peut etre eteinte volontairement 1 fois par semaine : ce n'est
pas une panne grave). Applis : Homepage, Prometheus, Grafana, node-exporter, xmrig (mineur),
Immich (photos, namespace immich ; il peut etre volontairement EN PAUSE avec 0 replica :
ce n'est pas un probleme, signale-le juste en une ligne dans le resume).

A partir des donnees brutes ci-dessous, ecris en francais un rapport court pour un mail :
1. Premiere ligne : un verdict global parmi  OK / A SURVEILLER / PROBLEME.
2. Les problemes eventuels, du plus grave au moins grave, avec la cause probable
   et la commande a lancer pour corriger ou investiguer.
3. Un resume en quelques puces : noeuds, applis, stockage, ressources.
Reste factuel, n'invente rien qui n'est pas dans les donnees. Texte brut, pas de markdown lourd.
Pas plus de 30 lignes."

DATA="$(collect)"

if [ -x "$CLAUDE_BIN" ]; then
  RESUME="$(printf '%s\n\nDONNEES:\n%s\n' "$PROMPT" "$DATA" \
    | timeout 300 "$CLAUDE_BIN" -p --tools "" --model sonnet 2>&1)"
  rc=$?
else
  RESUME="(claude introuvable: $CLAUDE_BIN)"; rc=1
fi
[ $rc -ne 0 ] && RESUME="!! Le resume par Claude a echoue (code $rc) :
$RESUME"

VERDICT="$(printf '%s' "$RESUME" | grep -m1 -oE 'PROBLEME|A SURVEILLER|OK' || echo '?')"
SUBJECT="[homelab] $VERDICT - rapport du $(date '+%d/%m')"

BODY="$RESUME

----------------------------------------------------------------
Donnees brutes :
$DATA"

if [ "$DRY_RUN" = "1" ]; then
  echo "Sujet : $SUBJECT"; echo; echo "$BODY"; exit 0
fi

: "${MAIL_TO:?MAIL_TO manquant dans $CONF}"
{
  echo "To: $MAIL_TO"
  echo "Subject: $SUBJECT"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo
  echo "$BODY"
} | msmtp -t
