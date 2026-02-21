# RISE Bare - Architecture Technique

## Vue d'ensemble

```
┌─────────────────────────────┐     SSH (port 22)     ┌─────────────────────────────┐
│   RISE Bare Client          │ ─────────────────────►│   Debian 12/13+ Server     │
│                             │                       │                             │
│  • Firewall Panel          │                       │  /usr/local/bin/           │
│  • Docker Panel            │                       │  • rise-firewall.sh        │
│  • Updates Panel           │                       │  • rise-docker.sh          │
│  • Health Check           │                       │  • rise-update.sh          │
│  • Server List            │                       │  • rise-onboard.sh         │
│  • SSH Keys Manager       │                       │  • rise-health.sh          │
└─────────────────────────────┘                       │  • setup-env.sh            │
                                                         └─────────────────────────────┘
```

---

## Partie 1 : Les Scripts Serveur

### 1.1 `setup-env.sh` - Installation des dépendances

**Version** : `1.0.0`

**Rôle** : Prépare le serveur en installant les outils nécessaires

**Commandes supportées** :
- `--install` : Installe nftables, jq, openssl, curl, wget si absents
- `--check` : Vérifie si les dépendances sont présentes

```bash
# Installation minimale
apt update
apt install -y nftables jq openssl curl wget git
```

---

### 1.2 `rise-onboard.sh` - Onboarding et gestion des clés SSH

**Version** : `1.0.0`

**Rôle** : Gère l'installation initiale et les clés SSH des appareils

**Commandes** :

| Commande | Description |
|----------|-------------|
| `--check` | Vérifie si RISE est déjà installé |
| `--finalize <ssh_key>` | Finalise l'installation, crée le user `rise-admin` |
| `--add-device <ssh_key>` | Ajoute une clé SSH pour un nouvel appareil |
| `--remove-device <ssh_key>` | Supprime une clé SSH |
| `--list-devices` | Liste toutes les clés enregistrées |

**Comportement** :
- Crée le user `rise-admin` avec accès SSH par clé uniquement
- Ajoute les clés dans `/home/rise-admin/.ssh/authorized_keys`
- Configure sudoers pour rise-admin (accès aux scripts RISE uniquement)

---

### 1.3 `rise-firewall.sh` - Gestion du pare-feu avec Fail2Ban

**Version** : `1.0.0`

**Rôle** : Gère les règles NFTables et Fail2Ban de manière atomique avec rollback automatique

**Commandes** :

| Commande | Description |
|----------|-------------|
| `--scan` | Scan les ports ouverts |
| `--apply` | Applique les règles (lit JSON depuis stdin) |
| `--confirm` | Confirme les règles après timeout de 60s |
| `--rollback` | Revient aux règles précédentes |

**Fail2Ban** :
- Activation automatique lors de l'installation
- Surveillance SSH par défaut
- Journalisation des tentatives bloquées

**Format JSON stdin** :
```json
[
  {"port": 22, "proto": "tcp", "action": "allow", "cidr": "0.0.0.0/0"},
  {"port": 80, "proto": "tcp", "action": "allow"},
  {"port": 443, "proto": "tcp", "action": "allow"}
]
```

**Format réponse JSON** :
```json
{
  "status": "success",
  "message": "Rules applied",
  "rollback_scheduled": true,
  "data": [...]
}
```

---

### 1.4 `rise-docker.sh` - Gestion Docker

**Version** : `1.0.0`

**Rôle** : Contrôle les containers Docker et les stacks docker-compose

**Commandes** :

| Commande | Description |
|----------|-------------|
| `--list` | Liste tous les containers |
| `--start <id>` | Démarre un container |
| `--stop <id>` | Arrête un container |
| `--restart <id>` | Redémarre un container |
| `--update <id>` | Stop, pull latest image, start |
| `--logs <id>` | Affiche les logs |
| `--compose-up <path>` | Lance docker-compose |
| `--compose-down <path>` | Arrête docker-compose |
| `--compose-pull <path>` | Met à jour les images |
| `--compose-add <git_url>` | Clone un dépôt et lance docker-compose |

**Format réponse `--list`** :
```json
{
  "status": "success",
  "data": [
    {"id": "abc123", "name": "nginx", "state": "running", "image": "nginx:latest"}
  ]
}
```

---

### 1.5 `rise-update.sh` - Gestion des mises à jour APT

**Version** : `1.0.0`

**Rôle** : Gère les mises à jour APT avec détection des mises à jour de sécurité et mises à jour granulaire

**Commandes** :

| Commande | Description |
|----------|-------------|
| `--check` | Vérifie les mises à jour disponibles |
| `--check-granular` | Vérifie avec liste de paquets spécifique |
| `--upgrade` | Installe toutes les mises à jour |
| `--upgrade-pkgs <packages>` | Met à jour uniquement les paquets spécifiés (JSON array) |

**Format `--check-granular` stdin** :
```json
{"packages": ["nginx", "openssl", "curl"]}
```

**Format réponse `--check`** :
```json
{
  "status": "success",
  "message": "10 updates available (2 security)",
  "data": {
    "packages": [
      {"name": "nginx", "current": "1.24.0", "available": "1.25.0", "security": true},
      {"name": "openssl", "current": "3.0.9", "available": "3.0.11", "security": true}
    ],
    "summary": {"total": 10, "security": 2}
  }
}
```

---

### 1.6 `rise-health.sh` - Vérification d'intégrité

**Version** : `1.0.0`

**Rôle** : Vérifie que la configuration serveur est intacte

**Vérifications** :
- `sudoers_file` : Fichier sudoers de rise-admin existe
- `ssh_dropin_clean` : Pas de configuration SSH personnalisée suspecte
- `nftables_include` : NFTables est configuré
- `scripts_present` : Tous les scripts RISE sont présents
- `fail2ban_status` : Fail2Ban est actif
- `docker_installed` : Docker est installé
- `rise_version` : Version des scripts

**Format réponse JSON** :
```json
{
  "status": "success",
  "version": "1.0.0",
  "checks": {
    "sudoers_file": "pass",
    "ssh_dropin_clean": "pass",
    "nftables_include": "pass",
    "scripts_present": "pass",
    "fail2ban_status": "pass",
    "docker_installed": "pass",
    "rise_version": "1.0.0"
  }
}
```

---

## Partie 2 : Le Client RISE Bare

### 2.1 Architecture Réseau

**Protocole** : SSH (port 22)

**Méthodes de connexion** :
1. **Password** : Connexion initiale avec login/password (pour onboarding)
2. **Key** : Connexion avec clé Ed25519 privée (après onboarding)

**Sécurité TOFU** :
- Sauvegarde l'empreinte du serveur lors de la première connexion
- Demande confirmation si l'empreinte change (possible attaque MITM)

---

### 2.2 Interface Utilisateur

**Fenetres** :

1. **Main Window**
   - Liste des serveurs configurés
   - Boutons Add/Remove Server
   - 4 onglets : Firewall, Docker, Updates, Health
   - Bouton Settings

2. **Onboarding Dialog**
   - Nom du serveur
   - IP/Hostname
   - Port SSH (défaut: 22)
   - Username (root ou sudo user)
   - Password
   - **3 modes de sécurité SSH** :
     - Mode 1 : Password pour tous (test uniquement)
     - Mode 2 : Clé SSH pour root, password pour autres utilisateurs
     - Mode 3 : Clé SSH pour tous (recommandé)

3. **Settings Dialog**
   - Sélecteur de langue (10 langues)
   - Case "Auto-update scripts on connect"
   - Lien donation Stripe
   - Bouton "Check for updates"

---

### 2.3 Flux Onboarding

```
1. User entre credentials (host, port, user, password)
2. Client SSH connect avec password
3. Script --check : RISE installé ?

   OUI → --add-device <clé_SSH_publique>

   NON → --install (setup-env.sh)
         --finalize <clé_SSH_publique>
         Configure SSH security mode

4. Génère clé Ed25519 pour ce device
5. Sauvegarde clé privée localement
6. Change username → rise-admin
7. Supprime le password de la config
```

---

### 2.4 Formats de données locaux

**Config serveurs** :
```json
{
  "servers": [
    {
      "id": "uuid",
      "name": "My Server",
      "host": "192.168.1.100",
      "port": 22,
      "username": "rise-admin",
      "password": null,
      "securityMode": "MODE_3"
    }
  ]
}
```

**Paramètres** :
```json
{
  "language": "en",
  "autoUpdateScripts": true,
  "lastUpdateCheck": "2024-01-15T10:30:00Z"
}
```

---

### 2.5 Internationalisation (i18n)

**Source** : Fichiers JSON sur GitHub avec gestion de versions
- URL : `https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/i18n/{lang}.json?version={version}`
- Version : Chaque fichier contient un champ `version`
- Langues : en, fr, de, es, zh, ja, ko, th, pt, ru
- Cache local avec vérification de version avant mise à jour

**Format fichier i18n** :
```json
{
  "version": "1.0.0",
  "app.title": "RISE Bare",
  ...
}
```

---

## Partie 3 : Options du Client

### 3.1 Firewall
- [x] Scanner ports ouverts
- [x] Ajouter règle (port, proto, action, CIDR)
- [x] Supprimer règle
- [x] Appliquer règles
- [x] Confirmer (après 60s)
- [x] Rollback
- [x] Status Fail2Ban
- [ ] **In-App Purchase** : Configuration Fail2Ban avancée

### 3.2 Docker
- [x] Lister containers
- [x] Start
- [x] Stop
- [x] Restart
- [x] Update (stop, pull, start)
- [x] Logs
- [x] Docker Compose: up/down/pull
- [x] **Docker Compose: ajout par URL GitHub**
- [ ] **In-App Purchase** : Éditeur Docker Compose visuel

### 3.3 Updates
- [x] Vérifier mises à jour
- [x] Mettre à jour tout
- [x] **Vérification granulaire par paquet**
- [x] **Mise à jour granulaire (paquets sélectionnés)**
- [ ] **In-App Purchase** : Historique des mises à jour

### 3.4 Health
- [x] Vérification intégrité complète
- [x] Affichage status (pass/fail] Version des)
- [x scripts
- [ ] **In-App Purchase** : Alertes automatisées par email

### 3.5 Server Management
- [x] Ajouter serveur
- [x] Supprimer serveur
- [x] Connexion auto
- [ ] **In-App Purchase** : Serveurs illimités (limite gratuite: 3)

---

## Partie 4 : Système d'Achat In-App (à implémenter)

### 4.1 Fonctionnalités Gratuites

| Fonctionnalité | Limite |
|----------------|--------|
| Serveurs gérés | 3 |
| APT upgrade | Tous |
| Docker | Start/Stop/Restart/Update |
| Docker Compose | up/down/pull |

### 4.2 Fonctionnalités Payantes (In-App Purchase)

| Fonctionnalité | Description |
|----------------|-------------|
| Serveurs illimités | Ajouter plus de 3 serveurs |
| APT granulaire | Sélectionner les paquets à mettre à jour |
| Docker Compose Editor | Interface visuelle pour modifier docker-compose |
| Docker Compose URL | Ajouter un dépôt GitHub directement |
| Alertes santé | Notifications par email en cas de problème |

### 4.3 Implémentation

Chaque fonction payante doit :
1. Vérifier le statut de l'achat via API
2. Si non acheté : afficher dialogue "Fonctionnalité payante" avec bouton donation/achat
3. Si acheté : exécuter la fonction normalement

---

## Partie 5 : Gestion des Versions

### 5.1 Stratégie de Versioning

**Scripts** : Chaque script contient sa propre version
- `setup-env.sh` : `VERSION="1.0.0"`
- `rise-onboard.sh` : `VERSION="1.0.0"`
- etc.

**Fichiers i18n** : Chaque fichier contient un champ `version`
- `en.json` : `"version": "1.0.0"`

**Client** : Version dans les paramètres
- `~/.rise/settings.json` : `"clientVersion": "1.0.0"`

### 5.2 Vérification des Mises à Jour

```
1. Au démarrage, le client check settings.lastUpdateCheck
2. Si > 24h ou autoUpdateScripts=true :
   a. Récupère version.json sur GitHub
   b. Pour chaque script : compare version locale vs remote
   c. Pour chaque fichier i18n : compare version
   d. Affiche liste des mises à jour disponibles
3. User peut choisir : tout mettre à jour, ou sélection partielle
```

---

## Annexe : Correspondance Scripts <-> UI

| UI Action | Script | Commande |
|-----------|--------|----------|
| Scan ports | rise-firewall | --scan |
| Add rule | rise-firewall | --apply (stdin) |
| Remove rule | rise-firewall | --apply (sans la règle) |
| Confirm rules | rise-firewall | --confirm |
| Rollback | rise-firewall | --rollback |
| List containers | rise-docker | --list |
| Start container | rise-docker | --start |
| Stop container | rise-docker | --stop |
| Restart container | rise-docker | --restart |
| Update container | rise-docker | --update |
| Docker compose up | rise-docker | --compose-up |
| Docker compose down | rise-docker | --compose-down |
| Docker compose pull | rise-docker | --compose-pull |
| Add GitHub compose | rise-docker | --compose-add |
| Check updates | rise-update | --check |
| Check granular | rise-update | --check-granular (stdin) |
| Upgrade all | rise-update | --upgrade |
| Upgrade selected | rise-update | --upgrade-pkgs (stdin) |
| Health check | rise-health | (no args) |
| Add device | rise-onboard | --add-device |
| Remove device | rise-onboard | --remove-device |
| List devices | rise-onboard | --list-devices |
