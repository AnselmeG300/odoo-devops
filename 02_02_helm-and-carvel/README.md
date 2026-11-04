# Sprint 2 - De Helm a Carvel

## Competences acquises

- Comprendre ce qu'apporte un outil de templating par rapport aux manifests bruts
- Lire et interpreter un chart Helm (culture DevOps) sans en faire l'outil principal
- Variabiliser la stack du Sprint 1 avec ytt (data values typees, fonctions, conditionnels)
- Surcharger la configuration par environnement sans dupliquer les manifests
- Patcher la sortie generee avec un overlay ytt, sans toucher au template de base
- Deployer un ensemble de ressources comme une application suivie avec kapp
- Lire un diff kapp avant application et comprendre le suivi d'etat (ownership par labels)

---

## Contexte

Au Sprint 1, la stack Odoo + PostgreSQL etait decrite en manifests natifs, puis
regroupee avec Kustomize (kubectl apply -k). Les valeurs (image, mot de passe, host,
replicas, taille du volume) etaient codees en dur dans chaque fichier. Pour un second
environnement, il fallait copier puis editer.

Ce sprint remplace cette approche par l'outillage reellement utilise dans l'entreprise
d'Ulrich : Carvel. Deux outils complementaires :

- ytt : le moteur de templating (il genere le YAML a partir de data values)
- kapp : le deployeur (il applique le YAML, en suit l'etat et montre un diff avant action)

Helm reste au programme, mais seulement pour la culture : savoir lire un chart. L'approche
principale est Carvel, car c'est la stack cible.

---

## Environnement

Utiliser KillerCoda : https://killercoda.com/playgrounds/scenario/kubernetes

- Cluster K8s pre-configure (1 control-plane + 1 worker)
- kubectl disponible
- La meme application que le Sprint 1 (Odoo + PostgreSQL)

Rappel Sprint 1 : l'Ingress controller NGINX n'est pas toujours pre-installe sur
KillerCoda. Si tu repars d'un cluster neuf, reinstalle-le comme a l'etape 7 du Sprint 1 :

```bash
kubectl get pods -A | grep -i ingress || \
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
```

### Installation de ytt et kapp

```bash
# Script officiel Carvel (installe ytt, kapp, imgpkg, kbld, vendir dans /usr/local/bin)
wget -O- https://carvel.dev/install.sh | bash

# Verification
ytt version
kapp version
```

Si le script ne passe pas, installer les deux binaires directement :

```bash
curl -sL -o /usr/local/bin/ytt  https://github.com/carvel-dev/ytt/releases/latest/download/ytt-linux-amd64
curl -sL -o /usr/local/bin/kapp https://github.com/carvel-dev/kapp/releases/latest/download/kapp-linux-amd64
chmod +x /usr/local/bin/ytt /usr/local/bin/kapp
```

---

## Arborescence du lab

```
02_helm-and-carvel/
  config/                    Templates ytt + schema + fonctions
    schema.yaml              Data values typees et documentees (les defauts = profil lab)
    helpers.lib.yaml         Fonctions partagees (labels) : l'equivalent de _helpers.tpl
    00-base.yaml             Namespace, ConfigMap, Secret, config Fluent Bit
    01-storage.yaml          PersistentVolume + PersistentVolumeClaim
    02-postgresql.yaml       StatefulSet PostgreSQL + Service
    03-odoo.yaml             Deployment Odoo (init + sidecar) + Service
    04-ingress.yaml          Ingress (regle sans host conditionnee hors prod)
    05-governance.yaml       NetworkPolicies + ResourceQuota + LimitRange
  values/
    values-prod.yaml         Surcharge production (ne redonne que ce qui change)
  overlays/
    prod-resources.yaml      Patch cible des ressources odoo en prod (overlay ytt)
```

---

## Partie 1 - Helm en bref (pour la culture, pas pour la prod)

Helm est le gestionnaire de paquets historique de Kubernetes. Un chart Helm est un dossier
qui templete des manifests avec le moteur GoTemplate et centralise les variables dans un
fichier values.yaml.

Exemple minimal de GoTemplate dans un chart :

```yaml
# values.yaml
image:
  repository: odoo
  tag: "19.0"
replicas: 1
```

```yaml
# templates/deployment.yaml (extrait)
spec:
  replicas: {{ .Values.replicas | default 1 }}
  template:
    spec:
      containers:
        - name: odoo
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

Commandes Helm a connaitre :

```bash
helm template odoo ./odoo-chart          # genere le YAML sans deployer (equivalent de ytt)
helm install  odoo ./odoo-chart -n odoo  # deploie
helm upgrade  odoo ./odoo-chart -n odoo  # met a jour
helm rollback odoo 1 -n odoo             # revient a une revision
helm uninstall odoo -n odoo              # supprime
```

Ce qu'il faut retenir de Helm : la notion de chart, de values, et le fait que le templating
se fait par substitution de chaines GoTemplate. Un chart Helm complet de cette meme stack a
existe comme version precedente de ce sprint : le lire est un bon exercice de culture.

### Pourquoi l'entreprise utilise Carvel plutot que Helm

- GoTemplate manipule du TEXTE avant que ce soit du YAML : une erreur d'indentation ne se voit
  qu'au deploiement. ytt manipule des noeuds YAML : beaucoup d'erreurs sont vues des la generation.
- Le values.yaml de Helm n'est pas type : une faute de frappe sur une cle passe en silence.
  Le schema ytt verifie les types et refuse une cle inconnue.
- Helm melange templating et deploiement dans un seul outil. Carvel separe clairement :
  ytt genere, kapp deploie. Chaque outil fait une chose.
- kapp montre un diff fiable avant d'appliquer et suit l'etat reel de l'application.

---

## Partie 2 - ytt : generer le YAML

ytt est le moteur de templating. Il lit les templates du dossier config/ et produit du YAML.

### Notions

1. Data values et schema (config/schema.yaml)

   Le fichier annote `#@data/values-schema` declare, type et documente toutes les valeurs
   configurables. Les valeurs ecrites dedans sont les DEFAUTS (ici le profil lab). Un fichier
   `#@data/values` separe peut surcharger ces defauts (voir values/values-prod.yaml).

2. Fonctions (config/helpers.lib.yaml)

   Les fragments repetes (labels) sont factorises dans des fonctions `#@ def ... #@ end`,
   l'equivalent du _helpers.tpl de Helm. Un seul endroit a corriger si la convention change.

3. Reference aux valeurs

   Dans un template : `#@ load("@ytt:data", "data")` puis `#@ data.values.odoo.tag`.
   Exemple : `image: #@ odoo.image + ":" + odoo.tag`.

4. Conditionnels

   `#@ if data.values.environment != "prod":` ... `#@ end` autour d'un bloc YAML.
   Utilise dans 04-ingress.yaml pour ne generer la regle sans host qu'hors production.

5. Modules integres

   `#@ load("@ytt:base64", "base64")` encode le Secret a la generation : on ne colle plus
   de chaines base64 a la main (voir 00-base.yaml).

### Commandes ytt

```bash
# Generer la stack en profil lab (defauts du schema)
ytt -f config/

# Generer en production (surcharge les defauts)
ytt -f config/ -f values/values-prod.yaml

# Generer en production avec l'overlay de ressources
ytt -f config/ -f values/values-prod.yaml -f overlays/prod-resources.yaml

# Surcharger une seule valeur en ligne de commande
ytt -f config/ --data-value odoo.replicas=3
```

### Overlays (overlays/prod-resources.yaml)

Un overlay modifie le YAML DEJA GENERE par matching, sans toucher au template de base.
On s'en sert quand la valeur a changer n'est pas exposee comme data value. Difference :

- data value : un parametre prevu, type, documente dans le schema
- overlay : un patch cible sur la sortie, pour les cas non prevus

---

## Partie 3 - kapp : deployer

kapp applique le YAML genere par ytt et le considere comme une APPLICATION (un ensemble de
ressources suivi sous un nom unique). A la difference de kubectl apply :

- kapp montre un DIFF avant d'appliquer et attend une confirmation
- kapp pose un label kapp.k14s.io/app sur chaque ressource : il sait exactement ce qui
  appartient a l'application, et supprime proprement ce qui a disparu du YAML
- kapp attend que les ressources soient reellement pretes (reconciliation) avant de rendre la main

### Commandes kapp

```bash
# Deployer : ytt genere, kapp applique l'application nommee "odoo"
ytt -f config/ | kapp deploy -a odoo -f - -n odoo

# Lister les applications gerees par kapp
kapp ls

# Inspecter les ressources de l'application et leur etat
kapp inspect -a odoo --tree

# Voir le diff d'un changement SANS l'appliquer
ytt -f config/ --data-value odoo.replicas=2 | kapp deploy -a odoo -f - -n odoo --diff-run

# Supprimer proprement toute l'application
kapp delete -a odoo
```

Note : l'option `-f -` lit le YAML depuis l'entree standard (la sortie de ytt). Le `|`
relie les deux outils : ytt genere, kapp deploie. C'est le coeur du flux Carvel.

---

## Etapes

### Etape 1 - Installer ytt et kapp

Voir la section Environnement. Verifier avec `ytt version` et `kapp version`.

### Etape 2 - Culture Helm (lecture seule)

Lire la Partie 1. Si le chart Helm de reference est present dans le repo, le rendre pour
comparer avec ytt :

```bash
helm template odoo ./odoo-chart | head -40
```

### Etape 3 - Generer la stack avec ytt (sans deployer)

```bash
ytt -f config/ | less
```

Reperer : le namespace injecte partout, le Secret encode en base64, les deux regles d'Ingress
(host + sans host) presentes en profil lab.

### Etape 4 - Changer une data value et observer

```bash
# Voir l'effet d'un changement de version sans toucher aux templates
ytt -f config/ --data-value odoo.tag=18.0 | grep 'image: odoo'
```

### Etape 5 - Deployer avec kapp

```bash
ytt -f config/ | kapp deploy -a odoo -f - -n odoo
```

kapp affiche un tableau des ressources a creer (couleur verte), demande confirmation (y),
puis attend que tout soit Ready. Suivre la convergence :

```bash
kubectl get pods -n odoo -w
```

Verifier (comme au Sprint 1) que postgresql-0 est 2/2 et le pod odoo 2/2, RESTARTS a 0.

### Etape 6 - Inspecter l'application

```bash
kapp ls
kapp inspect -a odoo --tree

# Le label pose par kapp sur chaque ressource de l'application
kubectl get all -n odoo -l kapp.k14s.io/app
```

### Etape 7 - Modifier et lire le diff kapp

```bash
# Augmenter le nombre de replicas Odoo et APPLIQUER : kapp montre le diff d'abord
ytt -f config/ --data-value odoo.replicas=2 | kapp deploy -a odoo -f - -n odoo
```

Observer que kapp ne recree pas tout : il ne modifie que le Deployment odoo (ligne jaune
"update"), le reste est inchange (aucune ligne). C'est le suivi d'etat.

### Etape 8 - Rendu production et overlay

```bash
# Rendu prod : une seule regle Ingress (host reel), storage 20Gi, 2 replicas
ytt -f config/ -f values/values-prod.yaml | grep -E 'host:|replicas:|storage:'

# Avec l'overlay : les ressources du conteneur odoo passent a 500m/1Gi
ytt -f config/ -f values/values-prod.yaml -f overlays/prod-resources.yaml \
  | grep -A6 'name: odoo$' | grep -A6 resources
```

### Etape 9 - Supprimer l'application

```bash
kapp delete -a odoo
```

kapp montre le diff de suppression (tout en rouge), demande confirmation, puis retire
uniquement les ressources de l'application odoo. Le PersistentVolume (reclaimPolicy Retain)
survit : voir le Sprint 1.

---

## Sprint 1 vs Sprint 2 - ce qui change

| Sprint 1 (manifests + Kustomize) | Sprint 2 (ytt + kapp) |
|----------------------------------|-----------------------|
| Valeurs codees en dur | Data values typees dans un schema |
| Copier/editer par environnement | Un seul config/, une surcharge par environnement |
| Patch limite (Kustomize) | Overlays ytt cibles sur la sortie |
| kubectl apply -k (pas de diff fiable) | kapp deploy (diff + confirmation) |
| Pas de suivi d'appartenance | kapp suit l'application par label, supprime le disparu |

## Carvel vs Helm

| | Helm | Carvel (ytt + kapp) |
|---|------|---------------------|
| Templating | GoTemplate (texte) | ytt (noeuds YAML) |
| Validation des valeurs | values.yaml non type | schema type, cle inconnue refusee |
| Erreurs d'indentation | vues au deploiement | souvent vues a la generation |
| Templating et deploiement | un seul outil | separes (ytt genere, kapp deploie) |
| Diff avant application | partiel | diff kapp clair, avec confirmation |

---

## Pour aller plus loin (Sprint 6)

Ici kapp est utilise en CLI : on genere avec ytt, on applique a la main. Au Sprint 6, le
kapp-controller et la ressource App (une CRD Carvel) feront tourner ce flux en continu
dans le cluster : le cluster se reconcilie tout seul vers l'etat decrit dans Git. C'est la
logique GitOps. ytt et kapp restent les memes briques, pilotees automatiquement.

---

## Depannage

### ytt : "Expected data values to conform to schema"

Une cle de values/values-prod.yaml n'existe pas dans config/schema.yaml, ou son type ne
correspond pas. Ajouter la cle au schema, ou corriger le type. C'est le garde-fou de ytt.

### kapp bloque sur "Waiting for ..."

Une ressource ne devient pas Ready. Ouvrir un autre terminal et diagnostiquer avec les
reflexes du Sprint 1 :

```bash
kubectl get pods -n odoo
kubectl describe pod <nom-pod> -n odoo
kubectl logs <nom-pod> -c odoo -n odoo
```

CrashLoopBackOff d'Odoo avec KeyError 'ir.http' : la base n'est pas initialisee. Verifier
que l'initContainer odoo-db-init s'execute bien avec "-d odoo_db -i base" (voir 03-odoo.yaml).

### 502 Bad Gateway dans le navigateur

Memes causes qu'au Sprint 1 : Ingress controller absent, endpoints vides, ou NetworkPolicy
qui bloque le trafic depuis ingress-nginx. Voir le depannage du Sprint 1.

---

## Questions de validation

1. Quelle est la difference entre ytt et kapp ? Lequel genere le YAML, lequel le deploie ?
2. Pourquoi un schema de data values est-il plus sur qu'un values.yaml Helm non type ?
3. Quand utiliser une data value, et quand utiliser un overlay ?
4. Que fait le `|` dans `ytt -f config/ | kapp deploy -a odoo -f -` ?
5. Comment kapp sait-il quelles ressources appartiennent a l'application odoo ?
6. Que montre kapp avant d'appliquer un changement, et pourquoi est-ce utile ?
7. Dans 04-ingress.yaml, pourquoi la regle sans host n'est-elle generee qu'hors production ?
8. Pourquoi encode-t-on le Secret avec base64.encode dans le template plutot qu'a la main ?
9. Si tu changes odoo.tag dans le schema, combien de fichiers dois-tu editer ? Pourquoi ?
10. Quel sera l'apport du kapp-controller au Sprint 6 par rapport a l'usage CLI de kapp ici ?
