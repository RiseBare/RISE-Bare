# RISE Bare — Plan de travail Flutter/dartssh2 v7.0
**Version:** 7.0 | **Date:** 2026-02-22 | **Référence:** RISE-Specs-V7.0.md  
**Agent cible:** minimax-m2.5 | **Statut:** PRÊT À EXÉCUTER

---

## Note préliminaire — Code source Java

**Le code Java doit être ignoré totalement.** Les specs V7.0 sont la seule source de vérité.  
Flutter et JavaFX sont des paradigmes opposés : toute tentative de "traduction" produira des anti-patterns dès le départ.

---

## Principe fondamental — Aucun fichier bundlé dans l'app

**L'application ne bundle aucun fichier de contenu dans ses assets.**  
Tout est téléchargé depuis GitHub au premier lancement et mis en cache localement.  
Les mises à jour sont granulaires : seuls les fichiers dont la version a changé sont re-téléchargés.

```
PREMIER LANCEMENT          LANCEMENTS SUIVANTS
─────────────────          ──────────────────────────────────────────
Cache vide                 Cache existant
→ Download TOUT            → Download manifest.json + i18n/version.json
→ Écran de chargement      → Comparer versions fichier par fichier
  "Initializing RISE..."   → Download uniquement les fichiers modifiés
→ App utilisable           → App utilisable immédiatement (cache = fallback)
```

---

## Structure du repo GitHub

```
RiseBare/RISE-Bare/
├── .gitignore
├── ports_db.json                    ← version + last_updated intégrés
├── manifest.json                    ← versions + SHA256 de tous les scripts
├── docs/
│   └── SECURITY_MODES.md
├── i18n/
│   ├── version.json                 ← manifest des versions de tous les fichiers i18n
│   ├── en.json  fr.json  de.json  es.json  zh.json
│   └── ja.json  ko.json  th.json  pt.json  ru.json
├── scripts/
│   ├── rise-firewall.sh
│   ├── rise-docker.sh
│   ├── rise-update.sh
│   ├── rise-onboard.sh
│   ├── rise-health.sh
│   └── setup-env.sh
└── tests/
    ├── integration/
    │   ├── test_firewall_workflow.bats
    │   ├── test_health_check.bats
    │   └── test_onboarding_flow.bats
    └── unit/
        ├── test_docker_sanitization.bats
        ├── test_firewall_json.bats
        ├── test_firewall_validation.bats
        └── test_onboard_validation.bats
```

### URLs GitHub Raw (base pour tous les téléchargements)

```
BASE = https://raw.githubusercontent.com/RiseBare/RISE-Bare/main

Scripts :    {BASE}/scripts/{nom}.sh
i18n :       {BASE}/i18n/{lang}.json
i18n index : {BASE}/i18n/version.json
ports_db :   {BASE}/ports_db.json
manifest :   {BASE}/manifest.json
```

---

## Structure du cache local

```
~/.rise/
├── servers.json              ← liste des serveurs configurés
├── settings.json             ← préférences app
├── known_hosts.json          ← fingerprints TOFU
├── keys/
│   ├── id_ed25519            ← clé privée device (stockée via flutter_secure_storage)
│   └── id_ed25519.pub        ← clé publique device
└── cache/
    ├── manifest.json         ← dernière version téléchargée du manifest scripts
    ├── ports_db.json         ← base des ports connue
    ├── i18n/
    │   ├── version.json      ← manifest des versions i18n
    │   ├── en.json
    │   ├── fr.json
    │   └── ...               ← 8 autres langues
    └── scripts/
        ├── rise-firewall.sh
        ├── rise-docker.sh
        ├── rise-update.sh
        ├── rise-onboard.sh
        ├── rise-health.sh
        └── setup-env.sh
```

---

## Formats des fichiers de versioning

### manifest.json — Versions + SHA256 des scripts (specs Section 4.2)

```json
{
  "version": "1.0.0",
  "last_updated": "2026-02-22T10:00:00Z",
  "scripts": [
    {
      "name": "rise-firewall.sh",
      "version": "1.0.0",
      "sha256": "<sha256hex>",
      "url": "https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts/rise-firewall.sh"
    }
  ]
}
```

### i18n/version.json — Manifest des versions i18n

```json
{
  "version": "1.0.0",
  "last_updated": "2026-02-22T10:00:00Z",
  "files": {
    "en": "1.0.0",
    "fr": "1.0.0",
    "de": "1.0.0",
    "es": "1.0.0",
    "zh": "1.0.0",
    "ja": "1.0.0",
    "ko": "1.0.0",
    "th": "1.0.0",
    "pt": "1.0.0",
    "ru": "1.0.0"
  }
}
```

### Chaque fichier i18n — Format corrigé (specs Section 13.F)

```json
{
  "version": "1.0.0",
  "app.title": "RISE Bare",
  "onboarding.title": "Add Server",
  ...
}
```

⚠️ **Gap actuel :** Les fichiers i18n dans le bucket n'ont **pas** de champ `version`. Ce champ est obligatoire selon les specs. **L'agent doit l'ajouter à tous les fichiers avant de les pousser sur GitHub.**

### ports_db.json — Déjà correct

```json
{
  "version": "1.0.0",
  "last_updated": "2026-02-19T00:00:00Z",
  "ports": [ ... ]
}
```

Comparaison lors du check : champ `version` + `last_updated`.

---

## Architecture Flutter cible

```
rise_bare/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/
│   │   ├── ssh/
│   │   │   ├── ssh_client.dart
│   │   │   ├── tofu_verifier.dart
│   │   │   └── command_executor.dart
│   │   ├── models/
│   │   │   ├── server.dart
│   │   │   ├── known_host.dart
│   │   │   └── app_settings.dart
│   │   ├── storage/
│   │   │   ├── servers_storage.dart
│   │   │   ├── known_hosts_storage.dart
│   │   │   └── settings_storage.dart
│   │   ├── cache/
│   │   │   ├── cache_manager.dart        ← orchestrateur principal
│   │   │   ├── script_cache.dart         ← gestion scripts bash
│   │   │   ├── i18n_cache.dart           ← gestion fichiers i18n
│   │   │   └── ports_db_cache.dart       ← gestion ports_db.json
│   │   ├── crypto/
│   │   │   └── key_manager.dart
│   │   └── i18n/
│   │       └── i18n_service.dart
│   │
│   ├── features/
│   │   ├── startup/                      ← premier lancement + initialisation
│   │   ├── onboarding/
│   │   ├── firewall/
│   │   ├── docker/
│   │   ├── updates/
│   │   ├── health/
│   │   ├── settings/
│   │   └── notifications/
│   │
│   └── widgets/
│
└── pubspec.yaml                          ← PAS de section assets/
```

### Dépendances pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  dartssh2: ^5.x
  flutter_secure_storage: ^9.x   # Clé privée SSH
  path_provider: ^2.x             # Chemins ~/.rise/
  http: ^1.x                      # Téléchargements GitHub
  crypto: ^3.x                    # SHA256 vérification scripts
  json_annotation: ^4.x
  provider: ^6.x                  # State management
  uuid: ^4.x
  flutter_localizations:
    sdk: flutter
  intl: any

dev_dependencies:
  build_runner: any
  json_serializable: any
  flutter_test:
    sdk: flutter
  mockito: any

# AUCUNE section assets: — tout est téléchargé et mis en cache
```

---

## Phase 0 — Préparation du repo GitHub et du projet Flutter

**Durée estimée :** 1-2 jours | **Priorité : BLOQUANTE**

### 0.1 Corrections à apporter aux fichiers du repo GitHub

Ces tâches sont à faire **avant** tout développement Flutter car l'app en dépend dès le premier lancement.

#### 0.1.a — Ajouter le champ `version` aux 10 fichiers i18n

Chaque fichier `{lang}.json` doit commencer par :
```json
{
  "version": "1.0.0",
  ...clés existantes...
}
```

#### 0.1.b — Ajouter les clés i18n manquantes dans les 10 fichiers

Les fichiers existants couvrent l'onboarding de base, security modes, firewall, docker, updates, health et settings génériques. Les clés suivantes sont absentes et doivent être ajoutées (valeurs en anglais d'abord, traductions à compléter) :

| Section | Clés à créer |
|---------|-------------|
| Onboarding — Tab OTP | `onboarding.tab.password`, `onboarding.tab.otp`, `onboarding.otp.label`, `onboarding.otp.hint`, `onboarding.otp.instruction` |
| Fallback Tab 1→2 | `onboarding.fallback.message`, `onboarding.fallback.tryOtp` |
| OTP Display (Device A) | `otp.display.title`, `otp.display.instruction`, `otp.display.cancel`, `otp.display.countdown` |
| Serveur inaccessible | `server.unreachable.title`, `server.unreachable.updateIp`, `server.unreachable.remove`, `server.unreachable.ignore`, `server.unreachable.cancel` |
| Security tab — Clients | `keys.thisDevice`, `keys.revoke`, `keys.cannotRevokeSelf`, `keys.addNewClient` |
| Notifications | `notif.scriptUpdated`, `notif.i18nUpdated`, `notif.securityWarning`, `notif.otpConsumed`, `notif.otpExpired`, `notif.markAllRead` |
| Firewall | `firewall.confirm`, `firewall.rollbackTimer`, `firewall.pendingExpired` |
| Docker Compose | `docker.compose.title`, `docker.compose.up`, `docker.compose.down`, `docker.compose.pull`, `docker.compose.rescan`, `docker.compose.delete`, `docker.compose.trash` |
| IAP | `iap.unlock`, `iap.unlimitedServers`, `iap.granularUpdate`, `iap.composeEditor`, `iap.composeGithub`, `iap.firewallReports`, `iap.fail2banEditor`, `iap.serverStats`, `iap.emailAlerts` |
| Auto-update | `settings.autoUpdateScripts`, `settings.autoUpdateScripts.tooltip`, `settings.checkUpdates` |
| Erreurs spécifiques | `error.errLocked`, `error.errPendingExpired`, `error.warnRootNoKey` |
| Initialisation | `startup.initializing`, `startup.downloading`, `startup.ready` |
| Cache/Updates | `cache.updating`, `cache.updateAvailable`, `cache.updatedCount` |

**Correction obligatoire :** `"settings.autoUpdate": "Auto-update scripts on connect"` → changer en `"settings.autoUpdateScripts"` avec la valeur correcte `"Auto-update scripts"` et tooltip `"Scripts are checked and updated at startup and every 6 hours"`.

#### 0.1.c — Créer `i18n/version.json`

Ce fichier n'existe pas encore dans le repo. L'agent doit le créer avec le format décrit ci-dessus, listant la version `"1.0.0"` pour les 10 langues.

#### 0.1.d — Créer `manifest.json` à la racine du repo

Ce fichier référencé par les specs (Section 4.2) n'est pas encore dans le bucket. L'agent doit le créer avec la version et le SHA256 de chacun des 6 scripts.

#### 0.1.e — Mettre à jour README.md

Remplacer toutes les références Java/JavaFX/Maven :
- Diagramme d'architecture : "RISE Client (JavaFX)" → "RISE Client (Flutter)"
- Section Requirements : supprimer "Java 21+" et "Maven 3.9+" → ajouter instructions d'installation Flutter par plateforme
- Section Quick Start : supprimer `mvn clean package` et `java -jar` → remplacer par téléchargement depuis store / release GitHub

#### 0.1.f — Mettre à jour SECURITY_MODES.md

- Section "Ajouter un nouvel appareil" : réécrire pour décrire les 3 flows (password, OTP Device B, ligne de commande)
- Remplacer "application RISE Java" par "application RISE Bare"
- Section tutoriels par OS (génération manuelle de clés) : conserver telle quelle — contenu technique valide et indépendant du langage client

### 0.2 Initialisation du projet Flutter

```bash
flutter create --org com.risebare --project-name rise_bare \
  --platforms ios,android,macos,linux,windows rise_bare
```

- Flutter stable ≥ 3.19 (Dart ≥ 3.3)
- **Aucune** section `assets:` dans `pubspec.yaml`
- Configurer les targets desktop

### 0.3 Modèles de données locaux (specs Section 2.5)

Implémenter avec `json_serializable` :

**servers.json :**
```dart
class ServerEntry {
  final String id;       // UUID
  final String name;     // Label local
  final String host;
  final int port;        // default 22
  final String username; // toujours "rise-admin" après onboarding
}
```

**known_hosts.json :**
```dart
class KnownHost {
  final String id;
  final String host;
  final int port;
  final String fingerprint; // "SHA256:..."
  final String algorithm;   // "ssh-ed25519"
  final DateTime firstSeen;
}
```

**settings.json :**
```dart
class AppSettings {
  final String language;
  final bool autoUpdateScripts;  // default: true
  final DateTime? lastUpdateCheck;
  final String clientVersion;
}
```

---

## Phase 1 — CacheManager (Priorité : BLOQUANTE)

**Durée estimée :** 2-3 jours  
**Cette phase doit être complète et testée avant toute autre chose.** L'ensemble de l'app en dépend.

### 1.1 Architecture du CacheManager

```dart
class CacheManager {
  // Point d'entrée unique — appelé au démarrage de l'app
  // Retourne un Stream de progression pour l'écran de chargement
  Stream<CacheInitProgress> initialize();

  // Appelé toutes les 6h en background (specs Section 12.2)
  Future<UpdateResult> checkAndUpdate();

  // Accès aux ressources depuis le cache local
  Future<List<Map<String, dynamic>>> getPorts();      // ports_db.json
  Future<Map<String, String>> getI18n(String lang);  // {lang}.json
  Future<String> getScriptPath(String name);         // path vers .sh en cache
  
  // État
  bool get isReady;              // true si cache initialisé
  bool get isFirstLaunch;        // true si cache était vide au démarrage
}

class CacheInitProgress {
  final String currentFile;   // fichier en cours de téléchargement
  final int downloaded;       // fichiers téléchargés
  final int total;            // total à télécharger
  final bool isComplete;
}

class UpdateResult {
  final int scriptsUpdated;
  final List<String> i18nUpdated;  // codes langues mis à jour
  final bool portsDbUpdated;
  final List<NotificationEntry> notifications; // pour le système de notifs
}
```

### 1.2 ScriptCache

```dart
class ScriptCache {
  // Télécharge manifest.json depuis GitHub
  // Compare version + SHA256 de chaque script avec le cache local
  // Download uniquement les scripts modifiés
  // Vérifie SHA256 après download — lève CacheIntegrityException si échec
  // Stocke dans ~/.rise/cache/scripts/
  Future<List<String>> syncScripts(); // retourne la liste des scripts mis à jour

  // Retourne le chemin local du script (pour SCP lors de l'onboarding)
  Future<String> getLocalPath(String scriptName);
  
  // Vérifie si tous les scripts requis sont présents en cache
  bool get isComplete;
}
```

**Validation SHA256 obligatoire :**
```dart
// Après chaque download de script
final bytes = await response.bodyBytes;
final digest = sha256.convert(bytes);
if (digest.toString() != expectedSha256) {
  throw CacheIntegrityException('SHA256 mismatch for $scriptName — tampering detected');
}
```

### 1.3 I18nCache

```dart
class I18nCache {
  // Télécharge i18n/version.json
  // Compare version de chaque langue avec le cache local
  // Download uniquement les fichiers modifiés
  // Vérifie que le champ "version" est présent dans chaque fichier
  Future<List<String>> syncI18n(); // retourne les codes langues mis à jour

  // Charge les clés pour une langue (depuis le cache)
  // Fallback: si la langue demandée n'est pas en cache → charger "en"
  Future<Map<String, String>> load(String langCode);
  
  // Liste des langues disponibles en cache
  List<String> get availableLanguages;
}
```

### 1.4 PortsDbCache

```dart
class PortsDbCache {
  // Télécharge ports_db.json depuis GitHub
  // Compare champ "version" avec le cache local
  // Download si version différente
  Future<bool> sync(); // true si mis à jour

  // Retourne la liste des ports connus (pour le panel Firewall)
  Future<List<PortEntry>> getPorts();
}
```

### 1.5 Flux de démarrage

```dart
// Dans main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cacheManager = CacheManager();
  
  runApp(RiseApp(cacheManager: cacheManager));
}

// Dans app.dart — premier widget affiché
class RiseApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: cacheManager.initialize().last, // attend la complétion du stream
      builder: (context, snapshot) {
        if (cacheManager.isReady) return MainScreen();
        return InitializationScreen(progress: snapshot.data);
      },
    );
  }
}
```

### 1.6 Écran d'initialisation (premier lancement)

Afficher pendant le téléchargement initial :
```
[Logo RISE]

Initializing RISE...
Downloading scripts (3/6)
rise-docker.sh

[ProgressBar]
```

Cet écran n'apparaît qu'au **premier lancement** (cache vide). Aux lancements suivants, l'app démarre directement depuis le cache pendant que la vérification se fait en background.

### 1.7 Timer de mise à jour automatique (specs Section 12.2)

Au démarrage ET toutes les 6 heures :
```dart
class AutoUpdateService {
  void start() {
    _checkAndUpdate(); // immédiat au démarrage
    Timer.periodic(Duration(hours: 6), (_) => _checkAndUpdate());
  }
  
  Future<void> _checkAndUpdate() async {
    if (!cacheManager.isReady) return;
    final result = await cacheManager.checkAndUpdate();
    
    if (settings.autoUpdateScripts && result.scriptsUpdated > 0) {
      // Pousser les scripts mis à jour sur chaque serveur configuré
      await _pushScriptUpdatesToServers(result);
    }
    
    // Générer les notifications (specs Section 12.3)
    await notificationService.addFromUpdateResult(result);
  }
}
```

**Comportement pendant update script sur un serveur (specs Section 12.2) :**
- Spinner sur l'entrée serveur dans la liste
- Opérations en queue (pas rejetées)
- Message si l'utilisateur tente une action : "Updating scripts, please wait…" + bouton Cancel
- Timeout de la queue : 30 secondes
- Si dépassé : action annulée, notification à l'utilisateur

### 1.8 Tests Phase 1

- Premier lancement : vérifier que tous les fichiers sont téléchargés
- Lancement suivant : vérifier que seuls les fichiers modifiés sont re-téléchargés
- Vérifier que la validation SHA256 rejette un fichier corrompu
- Vérifier que le fallback i18n → "en" fonctionne si la langue demandée est absente
- Vérifier le timer 6h
- Vérifier la queue d'opérations pendant un update script

---

## Phase 2 — Couche SSH / Core

**Durée estimée :** 2-3 jours  
**Aucune UI avant que cette phase soit validée.**

### 2.1 Gestionnaire de clés Ed25519

```dart
class KeyManager {
  // Génère une paire Ed25519 si elle n'existe pas encore
  // Une seule paire par device, réutilisée pour tous les serveurs (specs 2.4)
  Future<void> ensureKeyPair();
  
  // Retourne la clé publique formatée pour authorized_keys
  Future<String> getPublicKeyString();
  
  // Charge la clé privée pour dartssh2
  Future<dynamic> loadPrivateKey(); // type selon API dartssh2
}
```

⚠️ La clé privée est stockée via `flutter_secure_storage`, jamais en clair.  
⚠️ Si dartssh2 fournit une API de génération Ed25519, l'utiliser en priorité.

### 2.2 Vérificateur TOFU (specs Section 10.2)

```dart
class TofuVerifier {
  // Nouvelle connexion : prompt utilisateur → stocker dans known_hosts.json
  // Connexions suivantes : comparer fingerprint + algorithme
  // Fingerprint changé → BLOQUER → alerter possible MITM
  // Algorithme changé → BLOQUER → alerter possible downgrade attack
  Future<bool> verify(String host, int port, String fingerprint, String algorithm);
}
```

### 2.3 Client SSH principal

```dart
class RiseSshClient {
  Future<void> connectWithPassword(String host, int port, String user, String password);
  Future<void> connectWithKey(String host, int port, String user);
  Future<String> execute(String command, {required Duration timeout});
  
  // Upload d'un fichier via SFTP (pour déploiement scripts lors onboarding)
  Future<void> uploadFile(String localPath, String remotePath);
  
  Future<void> disconnect();
}
```

### 2.4 Exécuteur de commandes (specs Section 10.3)

```dart
enum CommandType {
  quick,        // 10s  — --scan, --list, --check (health)
  medium,       // 30s  — --start, --stop, --generate-otp, --finalize
  long,         // 120s — --compose-scan
  updateCheck,  // 220s — --check (apt)
  upgrade,      // 660s — --upgrade (apt)
}

class CommandExecutor {
  // Exécute via SSH, parse JSON, retourne Map<String, dynamic>
  // status == "error" → lève RiseCommandException
  // Timeout dépassé → lève TimeoutException
  Future<Map<String, dynamic>> run(
    RiseSshClient client,
    String command,
    CommandType timeout,
  );
}
```

Toutes les commandes RISE sont préfixées `sudo` :
```dart
await executor.run(client, 'sudo /usr/local/bin/rise-firewall.sh --scan', CommandType.quick);
```

### 2.5 Validation version API (specs Section 10.4)

```dart
class ApiVersionChecker {
  // Major différent → RiseIncompatibleApiException (bloquer opération)
  // Minor drift > 2 → retourner warning (permettre opération)
  CheckResult check(String serverVersion);
}
```

### 2.6 Gestion des codes d'erreur (specs Appendix B)

| Code | Comportement client |
|------|---------------------|
| `ERR_LOCKED` | Retry automatique après 2s, max 3 tentatives |
| `ERR_DEPENDENCY` | Alerter + proposer re-exécution `setup-env.sh` |
| `ERR_PENDING_EXPIRED` | Informer que les règles ont rollback, proposer re-apply |
| `ERR_ALREADY_CONFIGURED` | Informer silencieusement (déjà fait) |
| `WARN_ROOT_NO_KEY` | Warning lockout, demander confirmation explicite |

### 2.7 Tests Phase 2

- TOFU accepte une nouvelle clé après prompt
- TOFU rejette un fingerprint modifié
- TOFU rejette un changement d'algorithme
- Timeouts respectés pour chaque CommandType
- Parsing JSON success/error
- Validation API version (major/minor)
- ERR_LOCKED → retry automatique

---

## Phase 3 — Onboarding

**Durée estimée :** 3-4 jours  
**Référence specs :** Section 2.3 + Section 8.9

### 3.1 UI — Dialog "Add Server" (deux onglets)

**Tab 1 — "User/Pass Auth."** (défaut)
> *"Typically use this connection method to deploy RISE on a new server"*
- Server name (label local)
- IP / Hostname
- SSH port (défaut : 22)
- Username
- Password (masqué)
- [CANCEL] [CONFIRM]

**Tab 2 — "RISE OTP"**
> *"Typically use this connection method to connect to an existing RISE Bare server"*
- Server name (label local)
- IP / Hostname
- SSH port (défaut : 22)
- OTP code (6 chiffres, clavier numérique)
- Username implicitement `rise-admin` — non affiché
- [CANCEL] [CONFIRM]

**Fallback Tab 1 → Tab 2 :** Si `Permission denied (publickey)` :
> *"Connection failed. Try RISE OTP instead?"* → [CANCEL] [CONFIRM]  
→ CONFIRM : basculer Tab 2, pré-remplir IP et port, vider OTP

### 3.2 Phase 1 — Onboarding complet (nouveau serveur)

```
1. SSH connexion avec mot de passe
2. TOFU verification (prompt utilisateur)
3. KeyManager.ensureKeyPair()
4. sudo /usr/local/bin/rise-onboard.sh --check '<pubkey>'

   Routing selon réponse :
   ├── installed:false              → continuer étape 5
   ├── installed:true + key:false   → --add-device (étape 8)
   └── installed:true + key:true    → Phase 2 (ops normales)

5. Upload des 6 scripts depuis ~/.rise/cache/scripts/ via SFTP
   vers /tmp/ sur le serveur, puis déplacer vers /usr/local/bin/
6. sudo /usr/local/bin/setup-env.sh --install
7. sudo /usr/local/bin/rise-onboard.sh --finalize '<pubkey>'
8. Afficher Security Mode Dialog
9. Stocker fingerprint + server entry
```

**Source des scripts à uploader :** `~/.rise/cache/scripts/` — le CacheManager garantit qu'ils sont présents et valides (SHA256 vérifié).

### 3.3 Security Mode Dialog

| Mode | Label | Description |
|------|-------|-------------|
| 1 | Testing only — NOT RECOMMENDED | Root et autres users : méthodes actuelles inchangées |
| 2 | Transition | Root key-only, autres users inchangés |
| **3** | **Production — Recommandé** | Key-only pour tous |

Si mode 2 ou 3 : vérifier `WARN_ROOT_NO_KEY` → warning lockout + confirmation.  
Commande : `sudo /usr/local/bin/rise-onboard.sh --apply-security-mode <1|2|3> [--force]`

### 3.4 Phase 1b — Ajout device via mot de passe

Identique Phase 1 mais sans les étapes 5/6 — appeler `--add-device` directement.

### 3.5 Phase 1c — OTP Device B (nouveau device)

```
1. SSH avec password = OTP (username implicite : rise-admin)
2. TOFU verification
3. KeyManager.ensureKeyPair()
4. sudo /usr/local/bin/rise-onboard.sh --add-device '<pubkey>'
5. Stocker fingerprint + server entry
```

### 3.6 OTP Device A — Génération pour Device B

Depuis : Security Tab → "Add new RISE Bare client"

```
Boucle rolling toutes les 29 secondes :
  1. sudo /usr/local/bin/rise-onboard.sh --generate-otp
     → {otp, generated_at, window_seconds}
  2. Afficher OTP en grand format (6 chiffres lisibles)
  3. Compte à rebours 30s synchronisé sur generated_at (timestamp serveur)
  4. À T=29s → re-appeler --generate-otp automatiquement

À la fermeture du dialog :
  → Appeler --cancel-otp en background (fire-and-forget)
  → Si échec réseau : le timer serveur 90s gère le cleanup
```

---

## Phase 4 — Panel Firewall

**Durée estimée :** 3-4 jours | **Référence specs :** Section 5

### 4.1 Commandes

| Action UI | Commande | Timeout |
|-----------|----------|---------|
| Scanner ports | `rise-firewall.sh --scan` | QUICK |
| Appliquer règles | `rise-firewall.sh --apply` (stdin JSON) | MEDIUM |
| Confirmer | `rise-firewall.sh --confirm` | QUICK |
| Rollback | `rise-firewall.sh --rollback` | QUICK |
| Voir règles actives | `rise-firewall.sh --list` | QUICK |

### 4.2 Workflow Apply/Confirm/Rollback

```
1. Construire JSON des règles → envoyer via stdin à --apply
2. Afficher : "Rules applied. Confirm within 90 seconds."
3. Timer visible 90s côté client
4. [CONFIRM] → --confirm
   [Expiration] → rollback automatique côté serveur (client ne fait rien)

ERR_PENDING_EXPIRED sur --confirm → informer, proposer de ré-appliquer
```

### 4.3 Format stdin pour --apply

```json
{
  "rules": [
    {"action": "allow", "proto": "tcp", "port": 22,  "src": "0.0.0.0/0"},
    {"action": "allow", "proto": "tcp", "port": 443, "src": "0.0.0.0/0"}
  ]
}
```

### 4.4 Intégration ports_db

Lors de l'ajout d'une règle : auto-complétion du nom de service depuis `PortsDbCache.getPorts()`.  
Exemple : l'utilisateur entre le port `5432` → suggestion automatique "PostgreSQL Database".

---

## Phase 5 — Panel Docker

**Durée estimée :** 3-4 jours | **Référence specs :** Section 6

### 5.1 Containers

| Action | Commande | Timeout |
|--------|----------|---------|
| Lister | `rise-docker.sh --list` | QUICK |
| Démarrer | `rise-docker.sh --start <id>` | MEDIUM |
| Arrêter | `rise-docker.sh --stop <id>` | MEDIUM |
| Redémarrer | `rise-docker.sh --restart <id>` | MEDIUM |
| Mettre à jour | `rise-docker.sh --update <id>` | MEDIUM |
| Logs | `rise-docker.sh --logs <id>` | MEDIUM |

### 5.2 Docker Compose

| Action | Commande | Timeout |
|--------|----------|---------|
| Lister projets | `rise-docker.sh --compose-list` | QUICK |
| Rescan filesystem | `rise-docker.sh --compose-scan` | LONG |
| up / down / pull | `rise-docker.sh --compose-{up\|down\|pull} <path>` | MEDIUM |
| Supprimer | `rise-docker.sh --compose-delete <path> --mode <trash\|remove>` | MEDIUM |
| Purge volumes | `rise-docker.sh --compose-prune-volumes <v1,v2,...>` | MEDIUM |
| Purge networks | `rise-docker.sh --compose-prune-networks <n1,n2,...>` | MEDIUM |
| Vider corbeille | `rise-docker.sh --compose-trash-empty` | MEDIUM |
| Ajouter via Git URL *(IAP)* | `rise-docker.sh --compose-add <git_url>` | MEDIUM |

---

## Phase 6 — Panel Updates

**Durée estimée :** 2 jours | **Référence specs :** Section 7

| Action | Commande | Timeout |
|--------|----------|---------|
| Vérifier | `rise-update.sh --check` | UPDATE_CHECK (220s) |
| Upgrade tout | `rise-update.sh --upgrade` | UPGRADE (660s) |
| Upgrade sélectif *(IAP)* | `rise-update.sh --upgrade-pkgs` (stdin) | UPGRADE (660s) |

**Points importants :**
- `--check` peut prendre 3 min → progress bar indéterminée avec message explicatif
- `--upgrade` peut prendre 11 min → idem
- Validation nom packages côté client avant envoi : `^[a-z0-9][a-z0-9.+\-]{0,63}$`

---

## Phase 7 — Panel Health

**Durée estimée :** 2 jours | **Référence specs :** Section 9

Commande : `rise-health.sh` (sans argument) — Timeout QUICK (10s)

| Check | Affichage | Note |
|-------|-----------|------|
| `sudoers_file` | pass/fail/warn | |
| `ssh_dropin_clean` | pass/fail | Si fail → alerter "Leftover OTP config detected" |
| `nftables_include` | pass/fail | |
| `scripts_present` | pass/fail | |
| `fail2ban_status` | pass/fail | |
| `docker_installed` | pass/fail | |
| `docker_containers_rec_by_docker` | int | |
| `docker_containers_running` | int | |
| `rise_versions` | tableau | version de chaque script |
| `disk_space` | total/used/free/percent | |
| `memory` | total/used/free/percent | |
| `cpu` | cores + load avg 1/5/15min | |
| `network` | uptime + rx/tx bytes | client calcule débit moyen |
| `users` | liste | sudoers/sudo_group par user |

**Calcul débit réseau (client-side) :**
```dart
double rxMbps = (rxBytes / uptimeSeconds) * 8 / 1_000_000;
double txMbps = (txBytes / uptimeSeconds) * 8 / 1_000_000;
```

---

## Phase 8 — Settings, Notifications, Serveur inaccessible

**Durée estimée :** 2 jours | **Référence specs :** Sections 12.2, 12.3, 10.2b

### 8.1 Settings Dialog

- Sélecteur langue (10 langues)
- Checkbox "Auto-update scripts" + tooltip "Scripts are checked and updated at startup and every 6 hours"
- Lien Stripe donation
- Bouton "Check for updates" (déclenche `CacheManager.checkAndUpdate()`)

### 8.2 Notifications (specs Section 12.3)

Icône permanente top-right + badge count. Persistées entre sessions.

| Événement | Message |
|-----------|---------|
| Script mis à jour | "Firewall management script updated (v1.0.1)" |
| i18n mis à jour | "French language updated (v1.0.2)" |
| Nouvelle langue dispo | "Thai language now available" |
| Warning sécurité | "Temporary SSH config detected — check Health tab" |
| OTP consommé | "New device successfully added to [server name]" |
| OTP expiré | "OTP session expired — no device connected" |

### 8.3 Serveur inaccessible (specs Section 10.2b)

```
"Server '<n>' is unreachable."
  ○ Update IP / hostname   → modifier servers.json + effacer known_hosts entry + retry
  ○ Remove this server     → supprimer de servers.json + known_hosts (clé reste sur serveur)
  ○ Ignore for 30 minutes  → stocker suppression timestamp local
  ○ Cancel
```

---

## Phase 9 — IAP (In-App Purchase)

**Durée estimée :** 3-4 jours | **Priorité : BASSE**  
**Référence specs :** Section 11  
**À implémenter uniquement quand toutes les phases précédentes sont stables.**

### Principe fondamental

> **Les scripts serveur sont totalement ignorants de l'IAP.**  
> Tous les scripts exécutent toutes les commandes sans vérification de licence.  
> Le gate IAP vit exclusivement dans le client Flutter.

### Features libres vs payantes

| Feature | Limite free | IAP |
|---------|-------------|-----|
| Serveurs | **3 max** | Unlimited servers |
| APT upgrade | Tout d'un coup | Granular (`--upgrade-pkgs`) |
| Docker | Start/Stop/Restart/Update/Logs | — |
| Docker Compose | up/down/pull | Editor, GitHub URL |
| Firewall | Scan/Apply/Confirm/Rollback | Reports, Fail2Ban Editor |
| Health | Basic check | Server Stats détaillés |
| Email Alerts | — | IAP |

### Pattern Gate (Dart)

```dart
void onGranularUpdateTapped() {
  if (!iapManager.isPurchased(Feature.aptGranular)) {
    showPremiumDialog(Feature.aptGranular);
    return; // Aucun appel SSH
  }
  performGranularUpdate(selectedPackages);
}
```

---

## Tests — Fichiers .bats existants

Les fichiers `.bats` du repo testent **uniquement les scripts bash serveur** via BATS (Bash Automated Testing System). Ils sont **totalement indépendants du langage client** — aucune référence à Java dans aucun de ces fichiers.

**Organisation dans le repo :**
```
tests/
├── integration/              ← tests nécessitant un serveur RISE réel
│   ├── test_firewall_workflow.bats
│   ├── test_health_check.bats
│   └── test_onboarding_flow.bats
└── unit/                     ← tests sans infrastructure
    ├── test_docker_sanitization.bats
    ├── test_firewall_json.bats
    ├── test_firewall_validation.bats
    └── test_onboard_validation.bats
```

**Action de l'agent :** Conserver et utiliser tels quels dans la CI GitHub Actions pour valider les scripts bash de façon indépendante du client Flutter. Créer un workflow `.github/workflows/test-scripts.yml`.

**Tests Flutter à créer séparément** dans `rise_bare/test/` pour tester la couche client (CacheManager, SSH, parsers JSON, TOFU, etc.).

---

## Ordre de livraison recommandé

```
Itération 1 : Phase 0 (repo GitHub + corrections fichiers)
              → Pousser les corrections i18n, créer manifest.json et i18n/version.json
              → Initialiser le projet Flutter

Itération 2 : Phase 1 (CacheManager)
              → Valider avec un vrai download depuis GitHub
              → Vérifier SHA256, versioning granulaire, fallback i18n

Itération 3 : Phase 2 (SSH core)
              → Valider avec une vraie connexion SSH + TOFU

Itération 4 : Phase 3 (Onboarding)
              → Valider les 3 scénarios de bout en bout sur vrai serveur

Itération 5 : Phase 4 + Phase 7 (Firewall + Health)
              → Ces panels valident l'architecture SSH/JSON complète

Itération 6 : Phase 5 + Phase 6 (Docker + Updates)

Itération 7 : Phase 8 (Settings + Notifications + Serveur inaccessible)

Itération 8 : Phase 9 (IAP) — uniquement quand tout le reste est stable
```

---

## Checklist de validation finale

**Repo GitHub :**
- [ ] `manifest.json` créé à la racine avec SHA256 de chaque script
- [ ] `i18n/version.json` créé avec toutes les langues
- [ ] Champ `version` ajouté dans les 10 fichiers i18n
- [ ] Clés i18n manquantes ajoutées dans les 10 fichiers
- [ ] `README.md` mis à jour (Flutter, plus Java)
- [ ] `SECURITY_MODES.md` mis à jour (flow OTP Device A/B)

**Client Flutter :**
- [ ] Premier lancement : tous les fichiers téléchargés et mis en cache
- [ ] Lancement suivant : seuls les fichiers modifiés sont re-téléchargés
- [ ] SHA256 rejeté si corrompu
- [ ] Onboarding : 3 scénarios fonctionnels
- [ ] Panel Firewall : scan + apply + confirm + rollback (timer 90s visible)
- [ ] Panel Docker : containers + compose
- [ ] Panel Updates : check + upgrade (progress bar pour opérations longues)
- [ ] Panel Health : tous les checks affichés
- [ ] Security tab : list devices + revoke + add via OTP + security mode
- [ ] Notifications persistées entre sessions
- [ ] Serveur inaccessible : 4 options fonctionnelles
- [ ] Auto-revocation guard actif (ne peut pas révoquer sa propre clé)
- [ ] TOFU rejette fingerprint ou algorithme modifié

---

*Document v2 — Intègre la structure complète du repo GitHub et le mécanisme de cache/download.*  
*Référence unique : RISE-Specs-V7.0.md. Le code Java existant est ignoré.*
