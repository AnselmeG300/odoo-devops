# Sprint 1 - Fondamentaux Kubernetes

## Competences acquises

- Creer et organiser des ressources Kubernetes dans un namespace dedie
- Deployer une application multi-tiers (frontend applicatif + base de donnees)
- Initialiser correctement la base de donnees d'une application au premier demarrage
- Installer et configurer un Ingress controller NGINX
- Exposer une application vers l'exterieur via Ingress et NodePort
- Securiser les communications entre pods avec des NetworkPolicies
- Gerer le stockage persistant et limiter les ressources d'un namespace
- Regrouper et deployer l'ensemble de la stack avec Kustomize (kubectl apply -k)

---

## Contexte

On deploie une application web (Odoo) et sa base de donnees PostgreSQL sur Kubernetes,
en utilisant uniquement les objets natifs K8s (sans Helm, sans outil tiers).
L'objectif est de comprendre chaque brique avant de les abstraire dans les sprints suivants.

## Environnement

Utiliser KillerCoda : https://killercoda.com/playgrounds/scenario/kubernetes

- Cluster K8s pre-configure (1 control-plane + 1 worker)
- kubectl disponible
- Un CNI actif (fournit le reseau interne des pods)

Important : contrairement a ce qu'on pourrait croire, l'Ingress controller NGINX
n'est PAS toujours pre-installe sur les playgrounds KillerCoda. L'etape 7 verifie
sa presence et l'installe si necessaire. Sans controller, l'objet Ingress reste
inerte et l'acces renvoie un 502 Bad Gateway.

---

## Architecture cible

```
Internet / Navigateur
    |
    v
[Proxy KillerCoda]                (expose un port du noeud vers l'exterieur)
    |
    v
[NodePort 3XXXX] --> [Service ingress-nginx-controller : port 80]
    |
    v
[Pod Ingress controller NGINX]   (lit les regles Ingress, route le trafic)
    |
    v
[Ingress: odoo-ingress] --> [Service: odoo-svc (ClusterIP:8069)] --> [Deployment: odoo]
                                                                            |
                                                                            v
                                                        [Service: postgresql-svc (ClusterIP:5432)]
                                                                            |
                                                                            v
                                                        [StatefulSet: postgresql]
                                                                            |
                                                                            v
                                                        [PersistentVolumeClaim: postgresql-pvc]
                                                                            |
                                                                            v bind
                                                        [PersistentVolume: postgresql-pv]
                                                                            |
                                                                            v
                                                        [hostPath: /mnt/data/postgresql]
```

Point cle a retenir : les Services applicatifs (odoo-svc, postgresql-svc) sont en
ClusterIP, donc internes et non exposes a l'exterieur. Le seul point d'entree externe
de toute la stack est le NodePort du Service de l'Ingress controller.

---

## Application utilisee - Odoo

Odoo est un ERP (Enterprise Resource Planning) open-source. Il represente une application
multi-tiers realiste : un serveur applicatif qui depend d'une base de donnees, expose une
API HTTP, gere des fichiers, et produit des logs.

| Langage | Role dans Odoo |
|---------|---------------|
| Python 3 | Moteur principal : logique metier, ORM, serveur HTTP. Tous les modules back-end sont en Python. |
| XML | Definition des interfaces (formulaires, listes, menus) et donnees de configuration des modules. |
| JavaScript | Interface web reactive via le framework OWL (developpe par Odoo). |
| PostgreSQL | Base de donnees relationnelle. Odoo utilise son propre ORM Python pour generer le SQL. |
| SCSS/CSS | Styles de l'interface, bases sur Bootstrap. |

---

## Pattern sidecar - Log Exporter (Fluent Bit)

Les pods de ce sprint contiennent deux conteneurs : le conteneur principal et un sidecar
Fluent Bit. Fluent Bit est un collecteur de logs open-source (licence Apache 2.0), standard
dans les clusters Kubernetes pour collecter, filtrer et router les logs.

Pourquoi ce pattern ici : les conteneurs d'un meme pod partagent les memes volumes. Le sidecar
monte le meme emptyDir que le conteneur principal et lit les fichiers de logs qu'il y ecrit.
C'est la seule facon de collecter les logs d'une application qui ecrit dans des fichiers plutot
que vers stdout.

Note : la pratique moderne recommande d'ecrire vers stdout/stderr et de collecter via un
DaemonSet Fluent Bit sur chaque noeud. Le pattern sidecar reste pertinent quand l'application
ne peut pas etre modifiee pour ecrire vers stdout.

---

## Etapes

### Etape 1 - Namespace

Cree un namespace dedie pour isoler toutes les ressources.

```bash
kubectl apply -f manifests/00-namespace.yaml
kubectl config set-context --current --namespace=odoo
```

### Etape 2 - ConfigMap Fluent Bit

Configure le collecteur de logs avant de deployer les pods qui en dependent.

```bash
kubectl apply -f manifests/04b-fluent-bit-config.yaml
kubectl get configmap fluent-bit-config -n odoo
```

### Etape 3 - ConfigMap et Secret applicatifs

Le ConfigMap contient la configuration non sensible (nom de la base, host, user).
Le Secret contient les credentials (mot de passe) encodes en base64.

```bash
kubectl apply -f manifests/01-configmap.yaml
kubectl apply -f manifests/02-secret.yaml
kubectl get configmap -n odoo
kubectl get secret -n odoo
```

Verifie la coherence des credentials entre le ConfigMap et le Secret. Le user Odoo
(cle USER du ConfigMap) doit correspondre au role reellement cree par PostgreSQL,
et le mot de passe (cle POSTGRES_PASSWORD du Secret) doit correspondre.

### Etape 4 - PersistentVolume puis PersistentVolumeClaim

Deux objets distincts a creer dans l'ordre :

1. PersistentVolume (PV) : le stockage physique reel (cote cluster/administrateur)
2. PersistentVolumeClaim (PVC) : la demande de stockage (cote application)

Sur KillerCoda, la StorageClass par defaut (local-path) n'a pas de provisionner actif.
Il faut donc creer le PV manuellement avant le PVC (provisionning statique).

```bash
# 1. Creer le PersistentVolume (stockage physique sur le noeud)
kubectl apply -f manifests/03a-pv.yaml
kubectl get pv postgresql-pv
# STATUS doit afficher : Available

# 2. Creer le PersistentVolumeClaim (reservation du stockage)
kubectl apply -f manifests/03-pvc.yaml
kubectl get pvc -n odoo
# STATUS doit afficher : Bound
# VOLUME doit afficher : postgresql-pv
```

Le PVC doit passer en etat Bound avant de continuer. S'il reste en Pending, verifie que le PV
a bien ete cree et que les storageClassName correspondent (manual des deux cotes).

### Etape 5 - Base de donnees (StatefulSet + sidecar Fluent Bit)

Deploie PostgreSQL en tant que StatefulSet.

Pourquoi StatefulSet et pas Deployment : un StatefulSet garantit une identite reseau stable
(nom de pod previsible, ici postgresql-0) et un ordre de demarrage/arret, essentiel pour une
base de donnees.

```bash
kubectl apply -f manifests/04-postgresql-statefulset.yaml
kubectl apply -f manifests/05-postgresql-service.yaml
kubectl get pods -n odoo -w
```

Attends que le pod soit Running (READY 2/2 : postgresql + log-exporter).

```bash
kubectl get pods -n odoo
kubectl logs postgresql-0 -c log-exporter -n odoo
```

Verification du role et de la base (adapte le user si besoin) :

```bash
kubectl exec -n odoo postgresql-0 -c postgresql -- psql -U odoo_user -d odoo_db -c "\du"
```

### Etape 6 - Application Odoo (Deployment + sidecar Fluent Bit)

POINT CRITIQUE : initialisation de la base.

Odoo ne cree pas son schema tout seul au premier demarrage. Il faut lui demander
explicitement d'initialiser la base, en ciblant la base par son nom. Le piege classique
est d'utiliser "-i base" sans "-d odoo_db" : dans ce cas Odoo n'initialise rien, la base
reste vide, et l'application plante en boucle avec les erreurs :

```
KeyError: 'ir.http'
ERROR: relation "ir_module_module" does not exist
```

suivies d'un HTTP 500 sur /web/health et d'un CrashLoopBackOff.

Le manifest 06-odoo-deployment.yaml doit initialiser la base via un initContainer dedie,
qui s'execute apres l'attente de PostgreSQL et avant le conteneur principal. Les points cles :

```yaml
# initContainer d'initialisation (extrait)
- name: odoo-db-init
  image: odoo:16.0
  args:
    - -d
    - odoo_db            # cible explicitement la base (le correctif indispensable)
    - -i
    - base
    - --without-demo=all # optionnel : evite les donnees de demonstration
    - --stop-after-init  # initialise puis s'arrete proprement (exit 0)
  # env : HOST, PORT, USER (ConfigMap) + PASSWORD (Secret)

# conteneur principal (extrait)
- name: odoo
  image: odoo:16.0
  args:
    - -d
    - odoo_db            # sert l'application sur la base initialisee (plus de -i base ici)
  # startupProbe recommandee pour couvrir les ~60s de demarrage sans que
  # la livenessProbe ne tue le pod trop tot
```

L'initContainer est idempotent : au redemarrage, si la base est deja initialisee,
"-i base" est ignore et le conteneur ressort vite.

Deploiement :

```bash
kubectl apply -f manifests/06-odoo-deployment.yaml
kubectl apply -f manifests/07-odoo-service.yaml
kubectl get pods -n odoo -w
```

Suivi de l'initialisation de la base (l'initContainer cree le schema) :

```bash
kubectl logs -n odoo -l app.kubernetes.io/name=odoo -c odoo-db-init -f
```

Verifie que le pod Odoo affiche READY 2/2 (odoo + log-exporter) et que RESTARTS reste a 0.

```bash
kubectl get pods -n odoo
kubectl logs <nom-pod-odoo> -c log-exporter -n odoo
```

Test du health check en interne (doit renvoyer status pass/ok) :

```bash
POD=$(kubectl get pod -n odoo -l app.kubernetes.io/name=odoo -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n odoo $POD -c odoo -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8069/web/health
# Attendu : 200
```

### Etape 7 - Ingress controller NGINX (installation si absent)

L'objet Ingress (etape 8) n'est qu'une definition de regles. C'est le controller
(un pod NGINX) qui lit ces regles et route reellement le trafic. Sans controller,
l'Ingress est inerte et l'acces renvoie un 502.

Verifie d'abord s'il existe deja un controller :

```bash
kubectl get pods -A | grep -i ingress
kubectl get ingressclass
```

Si aucun pod ingress n'apparait, installe-le (variante bare-metal, exposition NodePort) :

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

L'installation cree, dans le namespace ingress-nginx : le Deployment du controller,
son Service (type NodePort), la ConfigMap, le RBAC, et l'IngressClass nginx. Le controller
et son Service sont des objets distincts livres par le meme manifest.

Recupere le port NodePort attribue au port 80 (necessaire pour l'acces navigateur) :

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Cherche le mapping du type 80:3XXXX/TCP, ou 3XXXX est ton port d'acces externe

# Extraction directe du nodePort :
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'
```

### Etape 8 - Ingress

Expose l'application via l'Ingress controller.

Specificite KillerCoda : le proxy de la plateforme frappe une IP:port et ne transmet PAS
le header "Host: odoo.lab.local" que la regle Ingress attend. Une regle avec host uniquement
renverrait alors un 404 du controller. On ajoute donc une seconde regle SANS host, qui matche
toute requete, en plus de la regle par host conservee pour la conformite pedagogique.

Le manifest 08-ingress.yaml doit contenir les deux regles :

```yaml
spec:
  ingressClassName: nginx
  rules:
    - host: odoo.lab.local          # regle 1 : routage par Host (pedagogique)
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: odoo-svc
                port:
                  number: 8069
    - http:                         # regle 2 : sans host, pour l'acces via proxy KillerCoda
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: odoo-svc
                port:
                  number: 8069
```

Applique et verifie :

```bash
kubectl apply -f manifests/08-ingress.yaml
kubectl get ingress -n odoo
# La colonne ADDRESS doit se remplir d'une IP (signe que le controller a pris en charge l'Ingress)

kubectl describe ingress odoo-ingress -n odoo
# La section Rules doit lister deux entrees : odoo.lab.local et * (regle sans host)
```

### Etape 9 - Acces a l'application

Validation interne de la chaine complete (controller -> service -> pod), en forcant le header Host :

```bash
CONTROLLER_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
kubectl run tmp --rm -it --image=busybox:1.35 -n odoo --restart=Never -- \
  wget -qO- --header="Host: odoo.lab.local" http://$CONTROLLER_IP/web/health
# Attendu : {"status": "pass"}
```

Acces navigateur via KillerCoda :

1. Recupere le nodePort du controller (etape 7).
2. Dans l'interface KillerCoda, ouvre le menu de ports ("Traffic / Select port to view on Host 1")
   et saisis ce nodePort (ex : 30687).
3. KillerCoda genere l'URL. Grace a la regle sans host, Odoo s'affiche via l'Ingress.

L'URL doit contenir le nodePort (ex : ...-30687.killercoda.com), pas 8069. Si elle contient
8069, tu passes par un port-forward direct qui court-circuite l'Ingress.

Preuve que le trafic passe bien par l'Ingress (a lancer avant de charger la page) :

```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller -f
# Les lignes GET /web/... defilent quand tu navigues
```

Connexion Odoo : email admin, mot de passe defini par ODOO_ADMIN_PASSWD dans le Secret.

### Etape 10 - NetworkPolicy

Applique les regles de securite reseau :

- Seule l'application peut parler a la base de donnees
- Seul l'Ingress controller peut joindre l'application
- Toute autre communication est bloquee par defaut

```bash
kubectl apply -f manifests/09-networkpolicy.yaml
```

Attention : les NetworkPolicy ne sont appliquees que si le CNI les supporte (Calico, Cilium :
oui ; Flannel seul : non). Verifie ton CNI :

```bash
kubectl get pods -n kube-system | grep -iE 'calico|cilium|flannel|weave|kindnet'
```

Point critique apres application : si une policy default-deny est active, elle peut bloquer
le trafic venant du namespace ingress-nginx vers le pod Odoo, ce qui recasse l'acces en 502.
Il faut alors autoriser explicitement l'entree depuis le namespace de l'Ingress controller :

```yaml
# extrait : autoriser l'Ingress controller a joindre Odoo sur 8069
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: ingress-nginx
    ports:
      - protocol: TCP
        port: 8069
```

Verifie que l'acces fonctionne toujours apres application des policies.

### Etape 11 - ResourceQuota

Limite les ressources consommables par le namespace entier.

```bash
kubectl apply -f manifests/10-resourcequota.yaml
kubectl describe resourcequota -n odoo
```

---

## Ordre recapitulatif des commandes (deploiement complet)

```bash
# 1. Namespace
kubectl apply -f manifests/00-namespace.yaml
kubectl config set-context --current --namespace=odoo

# 2. Config Fluent Bit
kubectl apply -f manifests/04b-fluent-bit-config.yaml

# 3. Config + Secret applicatifs
kubectl apply -f manifests/01-configmap.yaml
kubectl apply -f manifests/02-secret.yaml

# 4. Stockage
kubectl apply -f manifests/03a-pv.yaml
kubectl apply -f manifests/03-pvc.yaml

# 5. Base de donnees
kubectl apply -f manifests/04-postgresql-statefulset.yaml
kubectl apply -f manifests/05-postgresql-service.yaml

# 6. Application (avec init de la base)
kubectl apply -f manifests/06-odoo-deployment.yaml
kubectl apply -f manifests/07-odoo-service.yaml

# 7. Ingress controller (si absent)
kubectl get pods -A | grep -i ingress || \
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

# 8. Ingress
kubectl apply -f manifests/08-ingress.yaml

# 9. Securite reseau
kubectl apply -f manifests/09-networkpolicy.yaml

# 10. Quota
kubectl apply -f manifests/10-resourcequota.yaml
```

---

## Deploiement en une commande avec Kustomize

Kustomize est integre a kubectl (aucun outil tiers a installer, coherent avec l'esprit
"objets natifs" du sprint). Un fichier kustomization.yaml regroupe tous les manifests et
permet de deployer, verifier ou supprimer la stack en une seule commande.

### Fichier kustomization.yaml

A placer a la racine de sprint1-kubernetes-fundamentals/ (au meme niveau que le dossier
manifests/) :

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Injecte le namespace odoo dans toutes les ressources namespacees.
# Sans effet sur le PersistentVolume (cluster-scoped) ni sur l'objet Namespace.
namespace: odoo

# Labels communs ajoutes aux metadata uniquement.
# includeSelectors reste a false : ne pas toucher aux selectors des
# Deployment/StatefulSet, qui sont immuables une fois crees.
labels:
  - pairs:
      app.kubernetes.io/part-of: odoo-stack
      app.kubernetes.io/managed-by: kustomize
    includeSelectors: false

resources:
  - manifests/00-namespace.yaml
  - manifests/04b-fluent-bit-config.yaml
  - manifests/01-configmap.yaml
  - manifests/02-secret.yaml
  - manifests/03a-pv.yaml
  - manifests/03-pvc.yaml
  - manifests/04-postgresql-statefulset.yaml
  - manifests/05-postgresql-service.yaml
  - manifests/06-odoo-deployment.yaml
  - manifests/07-odoo-service.yaml
  - manifests/08-ingress.yaml
  - manifests/09-networkpolicy.yaml
  - manifests/10-resourcequota.yaml
```

### Commandes

```bash
# 0. Prerequis : installer l'Ingress controller (hors kustomization, voir plus bas)
kubectl get pods -A | grep -i ingress || \
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml

# 1. Verifier le YAML assemble sans rien appliquer
kubectl kustomize .

# 2. Deployer toute la stack
kubectl apply -k .

# 3. Suivre la convergence
kubectl get pods -n odoo -w

# 4. Supprimer toute la stack
kubectl delete -k .
```

### Points importants

Ordre et dependances : Kustomize envoie toutes les ressources a l'API sans attendre qu'un
pod soit Ready avant le suivant. Ce n'est pas un probleme ici, car les dependances sont gerees
par les mecanismes internes des manifests : l'initContainer wait-for-postgresql fait attendre
Odoo, le binding PVC/PV se resout de lui-meme, et les probes gerent le reste. La stack converge
seule meme si tout part en meme temps. C'est d'ailleurs un bon test de robustesse du montage.

Ingress controller hors kustomization : le controller est un composant d'infrastructure, pas
une ressource applicative. On le garde separe pour ne pas le desinstaller a chaque delete -k,
et pour ne pas melanger preparation du cluster et deploiement de l'application. On peut le
referencer comme ressource distante dans resources:, mais la separation reste plus propre.

namespace global : avec namespace: odoo dans la kustomization, on peut retirer les lignes
namespace: odoo repetees dans chaque manifest. Kustomize les injecte automatiquement.

labels et selectors : includeSelectors reste a false pour ne pas modifier les selectors des
Deployment et StatefulSet. Les modifier casserait un futur apply, car ces selectors sont
immuables apres creation.

### Pour aller plus loin (sprints suivants)

Kustomize permet aussi la generation de ConfigMap/Secret (configMapGenerator, secretGenerator)
et surtout les overlays : une base commune plus des variantes par environnement (dev, staging,
prod). Utile des que la stack se decline sur plusieurs environnements.

---

## Depannage - problemes rencontres et solutions

### Odoo en CrashLoopBackOff, logs avec KeyError 'ir.http'

Cause : la base odoo_db existe mais est vide (schema non cree). Vient d'un "-i base"
sans "-d odoo_db" dans les args du conteneur.

Diagnostic :

```bash
kubectl exec -n odoo postgresql-0 -c postgresql -- \
  psql -U odoo_user -d odoo_db -c "\dt" | grep ir_module_module
# Vide = base non initialisee
```

Solution : voir etape 6 (initContainer odoo-db-init avec -d odoo_db -i base --stop-after-init).

### 502 Bad Gateway dans le navigateur

Suspects, dans l'ordre :

```bash
# a. Endpoints du service (si <none> : pod pas Ready ou selector qui ne matche pas)
kubectl get endpoints -n odoo

# b. Le controller existe-t-il ? (souvent la vraie cause)
kubectl get pods -A | grep -i ingress

# c. Logs du controller pour la raison exacte
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=30

# d. Une NetworkPolicy bloque-t-elle le trafic de l'Ingress ?
kubectl get networkpolicy -n odoo
```

### 404 du controller via l'URL KillerCoda

Cause : le proxy KillerCoda n'envoie pas le header Host attendu. Solution : ajouter la regle
sans host dans l'Ingress (etape 8).

### Je ne vois pas de Service NodePort avec kubectl get svc

Cause : mauvais namespace. Le NodePort est dans ingress-nginx, pas dans le namespace courant.

```bash
kubectl get svc -A                    # vue de tous les namespaces
kubectl get svc -n ingress-nginx      # cible directe
```

---

## Commandes de debogage essentielles

```bash
kubectl get all -n odoo                                    # vue d'ensemble du namespace
kubectl logs -f deployment/odoo -n odoo                    # logs de l'application
kubectl describe pod <nom-pod> -n odoo                     # events (crashloop, etc.)
kubectl get svc -A                                         # services de tous les namespaces
kubectl get ingress -n odoo                                # etat de l'Ingress (colonne ADDRESS)
kubectl exec -it deployment/odoo -n odoo -- \
  bash -c "nc -zv postgresql-svc 5432"                     # test de connectivite reseau
```

---

## Commandes utiles - sidecar log-exporter

```bash
kubectl logs postgresql-0 -c log-exporter -n odoo
kubectl logs <pod-odoo> -c log-exporter -n odoo
kubectl logs -f postgresql-0 -c log-exporter -n odoo
kubectl exec -it postgresql-0 -c log-exporter -n odoo -- sh
kubectl exec -it postgresql-0 -c postgresql -n odoo -- ls /var/log/postgresql/
kubectl exec -it postgresql-0 -c log-exporter -n odoo -- ls /var/log/app/
```

---

## Questions de validation

1. Que se passe-t-il si tu supprimes le pod PostgreSQL ? Revient-il automatiquement ?
2. Quelle est la difference fondamentale entre un Deployment et un StatefulSet ?
3. Pourquoi encode-t-on les valeurs d'un Secret en base64 ? Est-ce du chiffrement ?
4. Quelle est la difference entre un PV, un PVC et une StorageClass ? Dans quel cas cree-t-on le PV manuellement ?
5. Que se passe-t-il si tu appliques le PVC avant le PV sur un cluster sans provisionner actif ? Comment diagnostiquer ?
6. Pourquoi "-i base" sans "-d odoo_db" empeche-t-il l'initialisation de la base Odoo ?
7. Quelle est la difference entre l'objet Ingress et l'Ingress controller ? Lequel route reellement le trafic ?
8. Pourquoi un objet Ingress ne suffit-il pas a exposer l'application sans controller ?
9. Pourquoi les Services odoo-svc et postgresql-svc sont-ils en ClusterIP et non en NodePort ?
10. Quel type de Service permet d'exposer l'Ingress controller a l'exterieur sur un cluster bare-metal ?
11. Apres application de la NetworkPolicy, essaie de curl la base depuis un autre namespace. Que se passe-t-il ?
12. Que se passe-t-il si tu tentes de creer un pod qui depasse les limites du ResourceQuota ?
13. Quelle est la difference entre un init container (wait-for-postgresql) et un sidecar (log-exporter) ?
14. Pourquoi le sidecar Fluent Bit peut-il lire les logs de PostgreSQL sans acceder au processus PostgreSQL lui-meme ?
15. Quel serait l'impact sur les logs si le sidecar log-exporter crashait ? PostgreSQL continuerait-il a fonctionner ?
16. Avec Kustomize, l'ordre des ressources dans le fichier garantit-il un ordre de demarrage strict ? Comment les dependances sont-elles alors gerees ?
17. Pourquoi ne pas inclure l'installation de l'Ingress controller dans la kustomization de l'application ?
```