# rfid - mini cluster MicroK8s maison

Master : laptop Asus (Ubuntu, noeud `csiaoh`)
Worker : VM Ubuntu (noeud `vmubuntu`), arretee au moins 1 fois par semaine.

## Ce qui a change par rapport a l'ancienne version

- `apps/` est remplace par `base/` (manifests generiques, sans IP ni nom de noeud)
  + `overlays/home/` (tout ce qui est specifique a TA maison).
- UN SEUL fichier de variables : `overlays/home/vars.env` (IP du master, pool, wallet).
  Les tags d'images sont aussi centralises dans `overlays/home/kustomization.yaml`.
- Plus de `deployment.yaml.j2` ni de generation Ansible pour Homepage.
- Plus de `nodeName` : on utilise des labels de noeuds (`homelab/role=master`,
  `miner=light`, `miner=full`). Quand la VM revient, le mineur repart tout seul.
- xmrig et node-exporter sont des DaemonSets (plus de Deployments dupliques).
- Prometheus decouvre les noeuds automatiquement (donc la VM est maintenant monitoree).
- Grafana et Prometheus ont un stockage persistant (PVC) et des probes.
- PriorityClass : le monitoring passe avant le mineur si le laptop manque de ressources.
- Les ConfigMaps sont generees par Kustomize avec un hash : si la config change,
  les pods redemarrent seuls. Le `rollout restart` du CI n'est plus necessaire.
- Le widget `widgets.yaml` de Homepage est enfin monte (il ne l'etait pas avant).
- Correction du playbook : le module snap est `community.general.snap`.

## Premier deploiement / migration depuis l'ancienne version

0. Prerequis Ansible (sur le master) :
   ansible-galaxy collection install community.general

1. Labels des noeuds (ou lance simplement `provisioning/site.yaml`, qui les pose) :
   microk8s kubectl label node csiaoh homelab/role=master miner=light --overwrite
   microk8s kubectl label node vmubuntu miner=full --overwrite

2. Addons necessaires :
   microk8s enable dns hostpath-storage metrics-server

3. (Optionnel mais recommande) mot de passe admin Grafana, AVANT le 1er demarrage
   avec stockage persistant (il n'est lu qu'a la creation de la base) :
   microk8s kubectl create secret generic grafana-admin \
     --from-literal=GF_SECURITY_ADMIN_PASSWORD='ton-mot-de-passe'

4. Nettoyer l'ancienne version AVANT d'appliquer (conflit de port 9100 et hugepages) :
   microk8s kubectl delete deployment node-exporter xmrig-miner-asus xmrig-miner-vm
   microk8s kubectl delete service node-exporter-service

5. Deployer :
   microk8s kubectl apply -k overlays/home

6. Nettoyer les anciennes ConfigMaps (remplacees par des versions avec hash) :
   microk8s kubectl delete configmap homepage-config prometheus-server-conf

Ensuite, chaque `git push` sur main redeploie automatiquement (voir .github/workflows).

## Modifier une variable

- IP du master, pool, wallet  -> overlays/home/vars.env
- Version d'une image         -> overlays/home/kustomization.yaml (section `images`)
- IP des machines (SSH)       -> provisioning/inventory/hosts.yaml
- Hugepages                   -> provisioning/group_vars/all.yml

Les tags d'images fournis sont des EXEMPLES : mets les dernieres versions stables
au moment du deploiement.

## Routine hebdomadaire : arreter la VM

Depuis le master :
  ./provisioning/scripts/vm-stop.sh     # cordon + drain + arret propre de la VM
  ... tes autres taches ...
  # redemarre la VM, puis :
  ./provisioning/scripts/vm-start.sh    # attend Ready + uncordon

Meme si tu oublies ces scripts, rien ne casse : seuls des DaemonSets tournent sur la
VM, ils reviennent seuls. Le master (monitoring, homepage) n'est pas affecte.
Dans Grafana/Prometheus, la VM apparaitra "down" pendant l'arret : c'est normal.
Si tu crees une alerte "noeud down", mets un delai (ex: 30 min) ou un silence.

## Depannage rapide

- Pod Grafana/Prometheus en "permission denied" sur le volume :
  verifie les droits du dossier hostpath (sudo chmod -R 777 sur le PV concerne).
- Pod xmrig en Pending : hugepages non reservees sur le noeud
  (cat /proc/meminfo | grep Huge) ; relance provisioning/site.yaml.
- Les rig-id dans le pool deviennent `csiaoh` et `vmubuntu` (nom du noeud)
  au lieu de `serveur-asus` / `vm-ubuntu`.
- Widget Kubernetes de Homepage vide : verifie `microk8s enable metrics-server`.

