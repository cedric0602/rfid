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
   microk8s enable dns hostpath-storage metrics-server ingress
   sudo usermod -aG microk8s $USER   # puis deconnexion/reconnexion (fait aussi par site.yaml)

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

## Immich (photos) - en test

- Serveur + base + cache sur le master, IA (visages, recherche) sur la VM.
- Acces : http://<IP du master>:30283 (site web et appli mobile).
- Le mot de passe de la base n'est pas dans git. A creer UNE fois avant le 1er deploiement :
    microk8s kubectl create namespace immich
    microk8s kubectl -n immich create secret generic immich-db \
      --from-literal=DB_PASSWORD="$(openssl rand -hex 24)"
- Mise a jour : changer les 2 tags Immich dans overlays/home/kustomization.yaml
  (et lire les notes de version : postgres/valkey sont figes dans base/immich).
- NAS plus tard : seul le PVC `immich-library` (les photos) ira sur le NAS ;
  la base `immich-db` doit rester en local.
- Bibliotheque externe : D:\photos du PC Windows (partage SMB "photos", compte
  Windows local "immich") monte en lecture seule sur le master dans /mnt/photos-externe
  (ligne dans /etc/fstab, identifiants dans /root/.smb-photos). Si le PC etait eteint
  au demarrage du master : sudo mount /mnt/photos-externe
  Dans Immich : Administration > Bibliotheques externes > dossier /mnt/photos-externe
- Tout supprimer : microk8s kubectl delete namespace immich
  (et retirer ../../base/immich de overlays/home/kustomization.yaml).

## Modifier une variable

- IP du master, pool, wallet  -> overlays/home/vars.env
- Version d'une image         -> overlays/home/kustomization.yaml (section `images`)
- IP des machines (SSH)       -> provisioning/inventory/hosts.yaml
                                 (+ NODE_IP / SSH_USER en tete de provisioning/scripts/vm-stop.sh)
- Hugepages                   -> provisioning/group_vars/all.yml

Les tags d'images fournis sont des EXEMPLES : mets les dernieres versions stables
au moment du deploiement.

## Routine hebdomadaire : arreter la VM

Depuis le master :
  ./provisioning/scripts/vm-stop.sh     # cordon + drain + arret propre de la VM
  ... tes autres taches ...
  # redemarre la VM, puis :
  ./provisioning/scripts/vm-start.sh    # attend Ready + uncordon

Nos applis sur la VM ne sont que des DaemonSets (ils reviennent seuls) et le monitoring
et Homepage restent sur le master. MAIS les pods systeme de MicroK8s (coredns,
metrics-server, hostpath-provisioner) peuvent tourner sur la VM : sans vm-stop.sh
(qui les deplace via le drain), DNS / widget Kubernetes peuvent etre en panne ~5 min.
Utilise donc les scripts.
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

