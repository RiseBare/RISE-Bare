# Modes de sécurité SSH pour RISE

Ce document explique les trois modes de sécurité SSH disponibles lors de l'onboarding d'un serveur avec RISE.

## Résumé des modes

| Mode | Accès root | Accès autres users | Recommandé |
|------|------------|-------------------|-----------|
| **Mode 1** | Password + Clé | Password + Clé | Non |
| **Mode 2** | Clé uniquement | Password + Clé | Pour transition |
| **Mode 3** | Clé uniquement | Clé uniquement | **Oui** |

---

## Mode 1 : Accès password pour tous (NON RECOMMANDÉ)

```bash
# Configuration : PasswordAuthentication yes
```

### Description
- Le compte utilisé pour l'onboarding (root ou sudo user) reste accessible par mot de passe
- Toutes les connexions SSH avec mot de passe restent possibles
- Aucune restriction sur l'authentification

### Risques
- **Attaques par force brute** possibles sur le compte
- Si le mot de passe est compromis, l'attaquant a un accès complet
- Vulnerable aux keyloggers et phishing
- Ne respecte pas les bonnes pratiques de sécurité

### Quand l'utiliser
- Uniquement en environnement de test/dev
- Migration temporaire vers le Mode 3
- Machines sans accès internet direct

---

## Mode 2 : Racine par clé, autres users par password (TRANSITION)

```bash
# Configuration sshd_config :
PermitRootLogin prohibit-password
PasswordAuthentication yes
```

### Description
- Le compte root (ou le compte sudo utilisé) n'est accessible que par clé SSH
- Les autres utilisateurs du système peuvent encore utiliser leur mot de passe
- Transition vers le Mode 3

### Avantages
- Le compte administratif principal est sécurisé par clé SSH
- Les clés SSH sont plus difficiles à compromettre que les mots de passe
- Réduit la surface d'attaque

### Inconvénients
- Les autres comptes restent vulnérables aux attaques par mot de passe
- Nécessite de se souvenir quelle machine utilise quel mode

### Quand l'utiliser
- Durant la phase de transition
- Serveurs avec plusieurs utilisateurs légitimes utilisant password

---

## Mode 3 : Clé SSH uniquement (RECOMMANDÉ)

```bash
# Configuration sshd_config :
PermitRootLogin prohibit-password
PasswordAuthentication no
```

### Description
- **Tous** les accès SSH nécessitent une clé SSH
- Le compte `rise-admin` est **toujours** en Mode 3 (clé uniquement)
- Le compte utilisé pour l'onboarding est aussi restreint aux clés

### Avantages
- **Sécurité maximale** : Pas de mot de passe à compromettre
- Les clés SSH Ed25519 sont cryptographiquement supérieures aux mots de passe
- Pas de risque d'attaques par force brute
- Conformité avec les standards de sécurité modernes
- Audit facilité (traçabilité des clés)

### Inconvénients
- Chaque nouvel appareil doit être enregistré via l'application RISE
- Perte de la clé privée = perte d'accès (prévoir des clés de backup)
- Configuration initiale plus longue

### Quand l'utiliser
- **Production** (fortement recommandé)
- Serveurs exposés sur internet
- Environnements sensibles
- Conformité PCI-DSS, SOC2, ISO 27001

---

## Gestion des clés SSH

### Ajouter un nouvel appareil

#### Méthode 1 : Depuis un appareil existant (OTP RISE)

Ceci est la méthode recommandée quand le serveur est déjà en Mode 2 ou Mode 3 (authentification par mot de passe désactivée).

Sur l'**appareil existant** (Appareil A) qui est déjà connecté au serveur :
1. Ouvrir l'application RISE Bare
2. Sélectionner le serveur
3. Aller dans l'onglet **Sécurité**
4. Cliquer sur **"Ajouter un nouveau client RISE Bare"**
5. Un code OTP à 6 chiffres s'affiche avec un compte à rebours de 30 secondes
6. Communiquer ce code à l'utilisateur du nouvel appareil (Appareil B)

Sur le **nouvel appareil** (Appareil B) :
1. Ouvrir l'application RISE Bare
2. Cliquer sur **"Ajouter un serveur"**
3. Sélectionner l'onglet **"RISE OTP"**
4. Entrer l'IP/hostname du serveur et le code OTP
5. L'application se connecte automatiquement et ajoute la clé SSH

#### Méthode 2 : Authentification par mot de passe (serveurs en Mode 1 uniquement)

Si le serveur est encore en Mode 1 (authentification par mot de passe activée) :
1. Lancer l'application sur le nouvel appareil
2. Cliquer "Ajouter un serveur"
3. Entrer les identifiants du serveur (IP, username, password)
4. L'application détecte que RISE est déjà installé
5. Ajoute automatiquement la nouvelle clé SSH

Via ligne de commande serveur :

```bash
# Générer une clé sur le nouvel appareil
ssh-keygen -t ed25519 -C "mon-nom-appareil"

# L'ajouter manuellement (si on a déjà accès SSH)
cat ~/.ssh/id_ed25519.pub
# Copier cette clé et l'ajouter via l'app RISE ou manuellement:
# echo "ssh-ed25519 AAAA..." >> /home/rise-admin/.ssh/authorized_keys
```

### Révoquer un appareil

**Important :** Vous ne pouvez pas révoquer votre propre accès depuis l'appareil actuel. Pour supprimer votre appareil actuel, vous devez :
1. Ajouter un nouvel appareil via OTP depuis cet appareil
2. Vous connecter depuis le nouvel appareil
3. Révoquer la clé de cet appareil depuis là

Via l'application RISE Bare (gestion des clés) :
1. Sélectionner le serveur
2. Aller dans "Paramètres" > "Clés SSH"
3. Cliquer sur "Révoquer" à côté de la clé à retirer

Via ligne de commande :
```bash
# Voir les clés enregistrées
rise-onboard.sh --list-devices

# Supprimer une clé spécifique
rise-onboard.sh --remove-device "ssh-ed25519 AAAA..."
```

### Clés de backup

Il est **fortement recommandé** de :
1. Générer une clé de backup sur un support sécurisé (clef USB chiffrée)
2. L'ajouter lors du premier onboarding ou après
3. Stocker cette clé de backup dans un coffre-fort physique

---

## Tutoriels : Ajouter des clés SSH par OS

### Windows

#### Option 1 : Via PowerShell (OpenSSH natif depuis Windows 10)

```powershell
# Générer une clé Ed25519
ssh-keygen -t ed25519 -C "mon-pc-windows"

# La clé publique est dans :
# C:\Users\<VotreNom>\.ssh\id_ed25519.pub
```

#### Option 2 : Via Git Bash

```bash
# Même commandes que Linux/Mac
ssh-keygen -t ed25519 -C "mon-pc-windows"
```

#### Option 3 : Via PuTTY

1. Télécharger PuTTYgen depuis https://www.putty.org
2. Sélectionner "Ed25519" en bas
3. Cliquer "Generate" et bouger la souris
4. Sauvegarder la clé privée ( bouton "Save private key")
5. Copier le texte dans "Public key for pasting" (commence par `ssh-ed25519`)

### macOS

```bash
# Générer une clé Ed25519
ssh-keygen -t ed25519 -C "mon-macbook-pro"

# Clé publique :
# ~/.ssh/id_ed25519.pub

# Pour l'ajouter à l'agent SSH (demande le mot de passe une fois)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

### Linux

```bash
# Générer une clé Ed25519
ssh-keygen -t ed25519 -C "mon-laptop-linux"

# Clé publique :
# ~/.ssh/id_ed25519.pub
```

### iOS (iPhone/iPad)

Utiliser une application comme **Termius** ou **Blink Shell** :

1. Dans l'app, aller dans "Keys" ou "SSH Keys"
2. Cliquer "+" pour générer une nouvelle clé
3. Sélectionner Ed25519
4. Copier la clé publique (format `ssh-ed25519 AAAA...`)

### Android

#### Option 1 : Termius
1. Télécharger Termius depuis Play Store
2. Créer un compte ou utiliser en local
3. Aller dans "Keychain" > "Generate Key"
4. Choisir Ed25519
5. Exporter la clé publique

#### Option 2 : JuiceSSH
1. Télécharger JuiceSSH
2.aller dans "Settings" > "Identity"
3. Créer une nouvelle identité avec clé SSH

---

##FAQ

**Q : Que faire si je perds toutes mes clés ?**
R : Se connecter physiquement au serveur (console) ou via un mécanisme de recovery (IPMI, cloud console) et ajouter une nouvelle clé manuellement.

**Q : Puis-je avoir plusieurs clés pour le même appareil ?**
R : Oui, c'est même recommandé pour séparer les usages (une clé pour le laptop, une pour le backup).

**Q : Les clés RSA sont-elles supportées ?**
R : Oui, mais Ed25519 est recommandé (plus sécurisé et plus rapide).

**Q : Le Mode 3 bloque-t-il SFTP ?**
R : Non, SFTP fonctionne avec les clés SSH exactement comme avec les mots de passe.

---

*Document généré pour RISE v1.0.0*
