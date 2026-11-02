# Sprint 2 — Helm et GoTemplate

## Compétences acquises

- Structurer un chart Helm à partir de manifests existants
- Utiliser la syntaxe GoTemplate pour variabiliser des manifests K8s
- Créer des named templates réutilisables dans `_helpers.tpl`
- Déployer la même application dans plusieurs environnements sans dupliquer le code

---

## Contexte

Les manifests du Sprint 1 fonctionnent, mais ils ont un problème : toutes les valeurs
(image, mot de passe, host, replicas) sont codées en dur. Impossible de les réutiliser
pour un autre environnement sans tout copier-coller et modifier manuellement.

Ce sprint transforme ces manifests en un **chart Helm** : une structure templétisée
où les variables sont centralisées dans `values.yaml` et injectées via GoTemplate.

---

## Notions à maîtriser avant de commencer

### 1. Structure d'un chart Helm

```
mon-chart/
├── Chart.yaml          → Métadonnées du chart (nom, version, description)
├── values.yaml         → Valeurs par défaut (surchargées à l'install)
└── templates/          → Manifests K8s avec variables GoTemplate
    ├── _helpers.tpl    → Fonctions réutilisables (named templates)
    ├── deployment.yaml
    ├── service.yaml
    └── ...
```

### 2. Syntaxe GoTemplate — référence rapide

| Syntaxe | Rôle | Exemple de résultat |
|---------|------|---------------------|
| `{{ .Values.image.tag }}` | Lire une valeur du `values.yaml` | `16.0` |
| `{{ .Release.Name }}` | Nom du release Helm | `my-app-dev` |
| `{{ .Release.Namespace }}` | Namespace cible | `production` |
| `{{ if .Values.ingress.enabled }}` | Condition | Génère ou non le bloc |
| `{{ range .Values.envVars }}` | Boucle sur une liste | Itère chaque variable |
| `{{ include "app.labels" . }}` | Appel d'un named template | Labels standards |
| `{{ .Values.db.password \| quote }}` | Pipe + fonction | `"mon_password"` |
| `{{ .Values.replicas \| default 1 }}` | Valeur par défaut | `1` si non défini |
| `{{ toYaml .Values.resources \| nindent 10 }}` | Bloc YAML indenté | Ressources K8s |

### 3. Le fichier `_helpers.tpl`

Centralise les fragments répétés dans tous les templates (labels, noms de ressources) :

```
{{- define "app.labels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

Utilisation dans n'importe quel template :
```yaml
metadata:
  labels:
    {{- include "app.labels" . | nindent 4 }}
```

### 4. Priorité des valeurs

```
values.yaml (défauts) < fichier -f (surcharge) < flag --set (surcharge directe)
```

```bash
helm install my-app ./mon-chart \
  -f values-prod.yaml \          # surcharge le values.yaml de base
  --set image.tag=2.0.0          # priorité maximale
```

---

## Commandes essentielles

```bash
# Vérifier la syntaxe du chart
helm lint ./mon-chart

# Voir les manifests générés SANS déployer
helm template my-app ./mon-chart

# Installer
helm install my-app ./mon-chart --namespace my-ns --create-namespace

# Mettre à jour après modification des values
helm upgrade my-app ./mon-chart --namespace my-ns

# Historique des déploiements
helm history my-app -n my-ns

# Rollback vers la version précédente
helm rollback my-app 1 -n my-ns

# Désinstaller
helm uninstall my-app --namespace my-ns
```

---

## Sprint 1 vs Sprint 2 — ce qui change

| Sprint 1 (manifests bruts) | Sprint 2 (chart Helm) |
|---------------------------|----------------------|
| Valeurs codées en dur | Variables dans `values.yaml` |
| Copier/modifier pour chaque env | Un seul chart, plusieurs fichiers values |
| Pas de versioning | `helm history` traçable |
| Rollback manuel | `helm rollback` en une commande |
| Aucune validation syntaxique | `helm lint` détecte les erreurs |

---

## Questions de validation

1. Comment déployer le même chart en INT avec une image différente sans modifier le chart ?
2. Que fait `nindent 6` dans `{{ toYaml .Values.resources | nindent 6 }}` ?
3. Quelle est la différence entre `helm install` et `helm upgrade --install` ?
4. Dans `_helpers.tpl`, à quoi servent les tirets dans `{{- define ... -}}` ?
5. Si `values.yaml` définit `replicas: 2` et que tu fais `--set replicas=5`, combien de pods seront créés ?
