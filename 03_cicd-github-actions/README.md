# Sprint 3 - Pipelines CI/CD avec GitHub Actions

## Competences acquises

- Comprendre la chaine CI/CD : du commit a l'application en production
- Piloter un cluster GKE a la main avec la CLI Google (gcloud) avant d'automatiser
- Construire et pousser une image Odoo personnalisee dans un registry
- Deployer cette image sur GKE avec ytt et kapp (suite du Sprint 2)
- Ecrire des workflows GitHub Actions : jobs, steps, needs, conditions
- Declencher un workflow a la main (workflow_dispatch) et entre deux repos (repository_dispatch)
- Separer le repo applicatif et le repo de deploiement, et les relier par un evenement
- Gerer les secrets et les acces (registry, compte de service Google)

---

## Methodologie du sprint : d'abord a la main, ensuite automatise

Ce sprint se fait en DEUX phases, dans cet ordre. On ne commence pas par la pipeline.

1. Phase 1 - Manuel : on fait chaque etape a la main, dans un terminal, avec gcloud,
   docker, ytt et kapp. On comprend precisement ce qui se passe, objet par objet.
2. Phase 2 - Automatise : on rejoue exactement ces memes etapes dans des workflows
   GitHub Actions. La pipeline ne fait rien de plus que ce qu'on a fait a la main.

Regle : tant qu'une etape n'est pas maitrisee a la main, on ne l'automatise pas.

---

## Arborescence du lab

```
03_cicd-github-actions/
  app-repo/                        Repo applicatif (logique) : construit l'image
    Dockerfile                     Image Odoo + addons maison
    addons/eazy_custom/            Addon de demonstration (justifie une image custom)
    .github/workflows/ci.yml       Pipeline CI : lint, build, push, declenchement CD
  deploy-repo/                     Repo de deploiement (logique) : deploie sur GKE
    config/                        Config Carvel du Sprint 2 (schema + templates)
    values/                        Surcharge prod
    overlays/                      Overlay prod
    .github/workflows/cd.yml       Pipeline CD : render ytt + deploy kapp sur GKE
```

Important : app-repo/ et deploy-repo/ sont deux depots GitHub SEPARES en conditions
reelles. Ici ils sont dans deux sous-dossiers pour tenir dans un seul lab. Quand tu
crees les vrais depots, le CONTENU de chaque sous-dossier devient la racine du depot
(le dossier .github/ doit etre a la racine du depot, sinon GitHub ignore le workflow).

Noms de depots utilises dans les exemples : odoo-app (applicatif) et odoo-deploy
(deploiement).

---

# =========================================================================
# PARTIE A - LES OBJETS ET LES INSTALLATIONS (a lire avant de commencer)
# =========================================================================

## A.1 - Les objets GitHub Actions

Chaque terme ci-dessous est un objet precis. On les retrouvera dans les workflows.

- Workflow : un fichier YAML dans .github/workflows/. Il decrit un pipeline complet.
  Un depot peut en avoir plusieurs (ci.yml, cd.yml).

- Evenement (mot-cle "on") : ce qui declenche le workflow. Exemples : push,
  workflow_dispatch, repository_dispatch. Un workflow peut ecouter plusieurs evenements.

- Job : une unite de travail du workflow, qui tourne sur une machine (runner). Par
  defaut, les jobs d'un workflow s'executent EN PARALLELE.

- needs : rend un job dependant d'un autre. "needs: lint" veut dire que le job ne
  demarre que si le job lint a reussi. C'est ainsi qu'on met les jobs en SEQUENCE.

- Step (etape) : une action unitaire dans un job. Soit une commande shell (run:),
  soit une action reutilisable (uses:). Les steps d'un job s'executent en ordre.

- Runner : la machine qui execute un job. Ici "ubuntu-latest", une VM Linux fournie
  par GitHub, neuve a chaque execution (donc on reinstalle les outils dans le job).

- Action (uses:) : un bloc reutilisable publie par GitHub ou la communaute. Exemples :
  actions/checkout (recupere le code), docker/build-push-action (build une image).

- if (condition) : n'execute un job ou un step que si une expression est vraie.
  Exemple : "if: github.ref == 'refs/heads/main'" limite au deploiement depuis main.

- env : des variables d'environnement, au niveau du workflow, d'un job ou d'un step.

- secrets : des valeurs sensibles stockees dans GitHub (Settings du depot), jamais en
  clair dans le code. On les lit avec ${{ secrets.NOM }}.

- GITHUB_TOKEN : un secret fourni AUTOMATIQUEMENT par GitHub a chaque execution. Il
  donne des droits sur le depot courant (par exemple pousser dans le registry GHCR du
  depot). Il ne permet PAS d'agir sur un autre depot : d'ou le PAT ci-dessous.

- PAT (Personal Access Token) : un jeton personnel que l'on cree soi-meme pour donner
  a un workflow des droits que le GITHUB_TOKEN n'a pas, par exemple declencher un
  workflow dans un AUTRE depot (ici le secret CD_DISPATCH_TOKEN).

- workflow_dispatch : un evenement qui ajoute un bouton "Run workflow" dans l'onglet
  Actions. Il permet de lancer le workflow A LA MAIN, avec des entrees (inputs).

- repository_dispatch : un evenement declenche par un APPEL d'API GitHub. Un depot
  (ou un systeme externe) envoie un evenement nomme, avec des donnees (client-payload).
  GitHub le recoit comme un webhook entrant et demarre le workflow qui l'ecoute. C'est
  ainsi que le repo applicatif declenche le repo de deploiement.

- Webhook : un appel HTTP envoye d'un systeme a un autre pour signaler un evenement.
  repository_dispatch repose sur ce mecanisme : la CI appelle l'API GitHub, GitHub
  livre l'evenement au repo de deploiement.

- Artifact : un fichier produit par un job et conserve, que d'autres jobs peuvent
  telecharger. Ici le job render produit rendered.yaml, le job deploy le recupere.

- permissions : les droits accordes au GITHUB_TOKEN pour un job. Exemple :
  "packages: write" pour autoriser le push dans GHCR.

## A.2 - Les objets Google Cloud (GCP)

- Projet (project) : le conteneur de toutes les ressources Google. Tout est rattache
  a un identifiant de projet (PROJECT_ID). La facturation est au niveau du projet.

- API : chaque service Google doit etre active dans le projet avant usage. Ici on
  active container.googleapis.com (GKE) et artifactregistry.googleapis.com (registry).

- Artifact Registry : le service Google qui stocke les images de conteneurs (et des
  paquets). C'est l'equivalent GCP de GHCR. Une image y a une adresse de la forme
  REGION-docker.pkg.dev/PROJECT_ID/DEPOT/IMAGE:TAG.

- GKE (Google Kubernetes Engine) : le service de cluster Kubernetes manage par Google.
  Un cluster GKE est ce sur quoi kapp deploie.

- Node pool : un groupe de machines (noeuds) du cluster, de meme type. Cree avec le
  cluster, detaille au Sprint 4.

- Ingress Controller (ingress-nginx) : le programme qui APPLIQUE les objets Ingress.
  Un Ingress seul n'est qu'une regle de routage : sans controleur, il n'a pas
  d'adresse et rien n'est expose. Le controleur integre a GKE ne traite que la
  classe "gce" ; notre Ingress utilise ingressClassName: nginx, il faut donc
  installer ingress-nginx. Son Service de type LoadBalancer fait creer par GCP un
  load balancer avec une IP publique : c'est la porte d'entree depuis Internet.

- Compte de service (service account) : un compte NON humain, pour qu'un programme
  (ici la pipeline) agisse sur GCP. Il a une adresse en ...iam.gserviceaccount.com.

- Cle de compte de service : un fichier JSON d'identifiants pour ce compte. On le
  stocke en secret GitHub (GKE_SA_KEY) pour que la CD s'authentifie. A ne jamais
  committer. (Alternative plus sure : Workload Identity Federation, hors scope ici.)

- Role IAM : un ensemble de droits attribue a un compte. Ceux utilises ici :
  - roles/container.developer   : deployer sur GKE (lire/ecrire les objets du cluster)
  - roles/artifactregistry.writer : pousser une image dans Artifact Registry
  - roles/artifactregistry.reader : tirer une image (lecture seule, pour le cluster)

## A.3 - Les installations

Toutes ces installations sont a faire sur la machine qui pilote (ton poste, ou une VM).
Les outils Carvel (ytt, kapp) sont ceux du Sprint 2.

### gcloud (la CLI Google)

```bash
# Debian / Ubuntu
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y google-cloud-cli

gcloud version
```

### kubectl et le plugin d'authentification GKE

```bash
# kubectl et le plugin requis par GKE, installes via gcloud
gcloud components install kubectl gke-gcloud-auth-plugin --quiet

# Si gcloud a ete installe par apt, les composants passent par apt :
sudo apt-get install -y kubectl google-cloud-cli-gke-gcloud-auth-plugin

kubectl version --client
```

### ytt et kapp (Carvel, comme au Sprint 2)

```bash
curl -sL -o /usr/local/bin/ytt  https://github.com/carvel-dev/ytt/releases/latest/download/ytt-linux-amd64
curl -sL -o /usr/local/bin/kapp https://github.com/carvel-dev/kapp/releases/latest/download/kapp-linux-amd64
chmod +x /usr/local/bin/ytt /usr/local/bin/kapp
ytt version
kapp version
```

### helm (pour installer l'Ingress Controller ingress-nginx)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### docker (pour construire l'image en Phase 1)

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # puis se reconnecter
docker version
```

### hadolint (lint du Dockerfile, utilise aussi par la CI)

```bash
sudo curl -sL -o /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
sudo chmod +x /usr/local/bin/hadolint
hadolint --version
```

---

# =========================================================================
# PARTIE B - PHASE 1 : TOUT A LA MAIN (gcloud, docker, ytt, kapp)
# =========================================================================

Objectif : deployer l'application sur GKE sans aucune pipeline, pour comprendre chaque
etape. On definit d'abord des variables reutilisees dans toutes les commandes.

```bash
export PROJECT_ID="mon-projet-gcp"          # ton identifiant de projet
export REGION="europe-west1"
export CLUSTER="odoo-cluster"
export AR_REPO="odoo"                         # nom du depot Artifact Registry
export IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/odoo-custom"
export TAG="v1"
```

## Etape 1 - S'authentifier et choisir le projet

```bash
gcloud auth login                      # ouvre le navigateur, connexion a ton compte
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
```

## Etape 2 - Activer les API necessaires

```bash
gcloud services enable container.googleapis.com artifactregistry.googleapis.com
```

## Etape 3 - Creer le depot d'images (Artifact Registry)

```bash
gcloud artifacts repositories create "$AR_REPO" \
  --repository-format=docker \
  --location="$REGION" \
  --description="Images Odoo EAZY"

# Autoriser docker a pousser vers cette region
gcloud auth configure-docker "$REGION-docker.pkg.dev"
```

## Etape 4 - Construire et pousser l'image Odoo personnalisee

```bash
cd app-repo
docker build -t "$IMAGE:$TAG" .
docker push "$IMAGE:$TAG"
cd ..
```

Verifier que l'image est bien en ligne :

```bash
gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO"
```

## Etape 5 - Creer le cluster GKE

```bash
gcloud container clusters create "$CLUSTER" \
  --region="$REGION" \
  --num-nodes=1 \
  --machine-type=e2-standard-2 \
  --release-channel=regular
```

Note : cette commande cree un cluster standard. La creation detaillee de
l'infrastructure (VPC, node pools, IAM) avec Terraform est le sujet du Sprint 4. Ici,
on cree un cluster simple a la main pour pouvoir deployer.

## Etape 6 - Recuperer les acces au cluster

```bash
gcloud container clusters get-credentials "$CLUSTER" --region="$REGION"

# Verifier la connexion (c'est ici qu'on utilise kubectl)
kubectl get nodes
```

## Etape 7 - Installer l'Ingress Controller (ingress-nginx)

Sans cette etape, l'Ingress odoo-ingress reste sans adresse : l'application n'est
joignable que depuis l'interieur du cluster (les Services sont en ClusterIP).

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --version 4.12.1 \
  --namespace ingress-nginx --create-namespace \
  --wait --timeout 5m

# Attendre que GCP attribue l'IP publique au load balancer (colonne EXTERNAL-IP)
kubectl get svc -n ingress-nginx ingress-nginx-controller -w
```

Points a retenir :
- `upgrade --install` est idempotent : relancer la commande ne casse rien.
- `--version` fige la version du chart (reproductible). Lister les versions
  disponibles : `helm search repo ingress-nginx --versions` (apres
  `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`).
- `--wait` attend que le controleur soit pret : son webhook d'admission doit
  repondre AVANT que kapp ne cree l'Ingress, sinon kapp echoue.
- Le nom du namespace (ingress-nginx) n'est pas libre : la NetworkPolicy
  odoo-netpol (config/05-governance.yaml) autorise justement ce namespace.
- Le projet ingress-nginx est en fin de maintenance (annonce de la communaute
  Kubernetes). Il reste valable pour ce lab ; la cible a terme est la Gateway API
  (par exemple le GKE Gateway Controller).

Le controleur est une brique d'infrastructure du cluster, installee une fois,
comme le cluster lui-meme. Il n'appartient pas a l'application kapp "odoo".

## Etape 8 - Deployer avec ytt et kapp (suite directe du Sprint 2)

```bash
cd deploy-repo

# Rendre la config Carvel en injectant l'image construite a l'etape 4
ytt -f config/ \
  --data-value odoo.image="$IMAGE" \
  --data-value odoo.tag="$TAG" \
  > rendered.yaml

# Verifier l'image qui sera deployee
grep "image:" rendered.yaml | grep odoo

# Deployer l'application sur GKE
kapp deploy -a odoo -n odoo -f rendered.yaml
cd ..
```

## Etape 9 - Verifier le deploiement et l'acces depuis Internet

```bash
kubectl get pods -n odoo -w         # attendre odoo et postgresql en Running 2/2
kapp inspect -a odoo -n odoo --tree

# L'Ingress doit afficher l'IP publique du load balancer dans ADDRESS
kubectl get ingress -n odoo
export LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$LB_IP"
```

Acceder a Odoo :
- En lab (environment: lab), la regle Ingress sans host est generee :
  `http://$LB_IP/` fonctionne directement depuis un navigateur.
- Par nom d'hote : odoo.lab.local n'est pas un vrai domaine. Ajouter la ligne
  `<LB_IP> odoo.lab.local` au fichier hosts du poste (/etc/hosts, ou
  C:\Windows\System32\drivers\etc\hosts sous Windows).
- En prod : creer un enregistrement DNS A odoo.monentreprise.com -> LB_IP. La regle
  sans host n'existe pas en prod, seul le nom de domaine fonctionne.

Attention : l'application est alors publique, en HTTP sans TLS. Le gestionnaire de
bases d'Odoo (/web/database/manager) est lui aussi joignable : definir un
admin_passwd fort (ou list_db = False) avant d'exposer durablement. Le TLS
(cert-manager + Let's Encrypt) viendra dans un sprint ulterieur.

A ce stade, tout a ete fait a la main. On sait exactement ce que la pipeline devra
faire. On peut automatiser.

---

# =========================================================================
# PARTIE C - PHASE 2 : AUTOMATISATION (GitHub Actions)
# =========================================================================

La pipeline rejoue la Phase 1 : construire l'image (CI), puis rendre et deployer (CD).
On la coupe en deux depots relies par un evenement, exactement comme dans l'entreprise.

## C.1 - Architecture a deux depots

```
   Developpeur
       |
       | git push (branche de travail, puis main)
       v
  +-----------------------+        repository_dispatch (webhook)     +------------------------+
  |  Repo applicatif      |  ------------------------------------->  |  Repo de deploiement   |
  |  odoo-app             |        event: new-image                  |  odoo-deploy           |
  |                       |        payload: image + tag              |                        |
  |  ci.yml :             |                                          |  cd.yml :              |
  |   lint -> build ->    |                                          |   render (ytt) ->      |
  |   push -> trigger     |                                          |   deploy (kapp) -> GKE |
  +-----------------------+                                          +------------------------+
```

Pourquoi deux depots : le code applicatif et la configuration de deploiement ont des
cycles de vie differents. On peut redeployer sans rebuild, et versionner la config a
part. C'est l'organisation retenue dans l'entreprise d'Ulrich.

## C.2 - Pipeline CI (odoo-app/.github/workflows/ci.yml)

Trois jobs en sequence grace a needs :

- lint : verifie le Dockerfile (hadolint).
- build : needs lint. Calcule le tag (SHA du commit), se connecte au registry,
  construit l'image. Le push n'a lieu que sur main (push: ${{ github.ref == main }}).
  Sur une branche feature/**, l'image est construite mais PAS poussee (branche de travail).
- trigger-deploy : needs build, et if main seulement. Envoie un repository_dispatch au
  depot odoo-deploy, avec l'image et le tag en payload.

Points a retenir dans ce workflow :
- outputs : le job build expose image_tag, reutilise par trigger-deploy.
- permissions packages: write : donne au GITHUB_TOKEN le droit de pousser dans GHCR.
- secrets.CD_DISPATCH_TOKEN : un PAT, car le GITHUB_TOKEN ne peut pas agir sur un autre depot.

## C.3 - Pipeline CD (odoo-deploy/.github/workflows/cd.yml)

Deux declencheurs :
- repository_dispatch (type new-image) : automatique, envoye par la CI.
- workflow_dispatch : manuel, avec des inputs (image, tag, environment lab ou prod).

Deux jobs en sequence grace a needs :
- render : resout les entrees (selon que l'on vient du dispatch ou du lancement manuel),
  installe ytt, rend la config Carvel en injectant image et tag, et publie rendered.yaml
  comme artefact. En environnement prod, il ajoute values-prod.yaml et l'overlay.
- deploy : needs render. Telecharge l'artefact, installe kapp, s'authentifie a Google
  (secret GKE_SA_KEY), recupere les acces GKE, verifie qu'ingress-nginx est present
  (et l'installe avec helm s'il manque, voir C.5 pour les droits), puis kapp deploy.

## C.4 - Les secrets a configurer

Dans odoo-app (Settings -> Secrets and variables -> Actions) :
- CD_DISPATCH_TOKEN : un PAT avec le droit "repo" sur odoo-deploy (pour le dispatch).
  Le GITHUB_TOKEN suffit pour pousser dans GHCR, pas besoin de secret pour le registry.

Dans odoo-deploy :
- GKE_SA_KEY : la cle JSON du compte de service Google (contenu complet du fichier).
- GKE_CLUSTER : le nom du cluster (ex. odoo-cluster).
- GKE_LOCATION : la region du cluster (ex. europe-west1).

## C.5 - Preparer le compte de service Google (une fois)

Ces commandes creent le compte que la CD utilisera, avec juste les droits necessaires.

```bash
export SA_NAME="gh-deployer"
export SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

# 1. Creer le compte de service
gcloud iam service-accounts create "$SA_NAME" \
  --display-name="GitHub Actions deployer"

# 2. Lui donner les droits : deployer sur GKE + lire les images
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/container.developer"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" --role="roles/artifactregistry.reader"

# Note ingress-nginx : son installation cree des objets a l'echelle du cluster
# (ClusterRole, ClusterRoleBinding, IngressClass, webhook). roles/container.developer
# ne le permet PAS. La CD se contente donc de verifier que le controleur est present
# et ne l'installe que s'il manque. Deux options :
#   - (recommande) installer ingress-nginx une fois a la main (Etape 7) :
#     container.developer suffit alors a la CD ;
#   - ou donner roles/container.admin au compte pour que la CD l'installe elle-meme
#     (plus de droits pour une cle stockee dans GitHub : a eviter hors lab).

# 3. Generer la cle JSON a coller dans le secret GKE_SA_KEY
gcloud iam service-accounts keys create key.json --iam-account="$SA_EMAIL"
# -> copier le contenu de key.json dans le secret GitHub GKE_SA_KEY, puis supprimer le fichier
rm -f key.json
```

Note registry dans la CI automatisee : la CI pousse ici dans GHCR (ghcr.io), zero
configuration avec le GITHUB_TOKEN. En Phase 1 manuelle, on a pousse dans Artifact
Registry (Google). Les deux approches sont montrees volontairement. Pour tout faire
chez Google, remplacer la connexion GHCR par une authentification Artifact Registry
dans la CI, et adapter env.REGISTRY et env.IMAGE_NAME.

## C.6 - Derouler la pipeline

```bash
# 1. Sur une branche de travail : build sans deploiement
git checkout -b feature/test-ci
git commit --allow-empty -m "test CI sur branche de travail"
git push origin feature/test-ci
# -> onglet Actions : lint + build passent, pas de push, pas de deploiement

# 2. Sur main : build + push + declenchement du deploiement
git checkout main
git commit --allow-empty -m "release"
git push origin main
# -> odoo-app deploie l'evenement, odoo-deploy se declenche et deploie sur GKE

# 3. Deploiement manuel (sans rebuild) : onglet Actions de odoo-deploy
#    -> Run workflow -> saisir image, tag, environment (lab ou prod)
```

---

## Sprint 2 vs Sprint 3

| Sprint 2 (deploiement a la main) | Sprint 3 (CI/CD) |
|----------------------------------|------------------|
| ytt et kapp lances manuellement | memes commandes, jouees par les pipelines |
| Image odoo:19.0 standard | image Odoo personnalisee construite par la CI |
| Un seul endroit, un seul geste | deux depots relies par repository_dispatch |
| Pas de trace des executions | historique complet dans l'onglet Actions |

## Ce que ca prepare

- Sprint 4 : l'infrastructure GKE (VPC, node pools, IAM) avec Terraform, au lieu de la
  creation a la main de l'etape 5.
- Sprint 6 : le GitOps avec kapp-controller. La pipeline poussera l'etat desire, le
  cluster se reconciliera tout seul, au lieu d'un kapp deploy lance par la CD.

---

## Depannage

### Le workflow ne se declenche pas
Verifier que le dossier .github/workflows/ est a la RACINE du depot GitHub, pas dans un
sous-dossier. Verifier aussi le nom de la branche dans la section on: push.

### repository_dispatch sans effet
Le PAT (CD_DISPATCH_TOKEN) doit avoir le droit "repo" sur odoo-deploy, et le nom du
depot cible (repository:) doit etre exact. L'erreur est souvent un 404 silencieux.

### denied: permission_denied sur le push d'image (GHCR)
Le job build doit avoir permissions: packages: write, et l'image doit etre prefixee par
ghcr.io/OWNER.

### get-gke-credentials echoue
Verifier GKE_CLUSTER et GKE_LOCATION, et que le compte de service a bien
roles/container.developer. Le plugin gke-gcloud-auth-plugin est installe par l'action.

### L'Ingress n'a pas d'ADDRESS / l'application n'est pas joignable
ingress-nginx n'est pas installe ou pas pret : `kubectl get pods -n ingress-nginx`
et `kubectl get ingressclass` (une classe "nginx" doit exister). Refaire l'Etape 7.
Si EXTERNAL-IP reste en `<pending>`, attendre 1 a 2 minutes (creation du load
balancer GCP) puis `kubectl describe svc -n ingress-nginx ingress-nginx-controller`.

### failed calling webhook "validate.nginx.ingress.kubernetes.io"
kapp a cree l'Ingress avant que le controleur soit pret. Relancer le deploiement une
fois les pods ingress-nginx en Running (c'est le role du --wait de helm).

### La CD echoue sur l'installation d'ingress-nginx (forbidden ... clusterroles)
Le compte de service n'a que roles/container.developer : installer ingress-nginx une
fois a la main (Etape 7), ou lui accorder roles/container.admin (voir C.5).

### kapp: Error: Asking for confirmation
En CI, kapp doit tourner avec --yes (non interactif). C'est deja le cas dans cd.yml.

---

## Questions de validation

1. Quelle est la difference entre un job et un step ?
2. Comment met-on deux jobs en sequence plutot qu'en parallele ?
3. A quoi sert "if: github.ref == 'refs/heads/main'" sur le job de deploiement ?
4. Pourquoi une branche feature/** construit l'image mais ne la pousse pas ?
5. Quelle est la difference entre workflow_dispatch et repository_dispatch ?
6. Pourquoi le GITHUB_TOKEN ne suffit-il pas pour declencher le depot de deploiement ?
7. Comment l'image construite par la CI arrive-t-elle jusqu'a la commande ytt de la CD ?
8. Pourquoi passe-t-on rendered.yaml par un artefact entre les jobs render et deploy ?
9. Quels roles IAM le compte de service de deploiement doit-il avoir, et pourquoi ?
10. Qu'est-ce qui, dans ce sprint, sera remplace par Terraform (Sprint 4) et par le
    kapp-controller (Sprint 6) ?
