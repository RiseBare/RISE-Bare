# IMPROVEMENTS.md - RISE-Bare

**Last Updated:** 2026-03-11

---

## Bugs à corriger

*(Aucun bug critique reporté)*

---

## Roadmap - Améliorations à implémenter

### Phase 1 - Tests & Validation
- [x] Ajouter des tests automatisés pour les scripts serveur
- [x] Ajouter validation des entrées utilisateur dans les scripts
- [x] Implémenter rate limiting sur les opérations firewall

### Phase 2 - Performance
- [x] Optimiser les requêtes nftables
- [x] Caching des règles côté client

### Phase 3 - CI/CD
- [ ] Réactiver les builds Windows (résoudre billing GitHub)
- [ ] Réactiver les builds macOS/iOS (résoudre billing GitHub)

### Phase 4 - Premium Features (In-App Purchase)
**Implémentation:** Toutes les features avec switches internes

- [x] PremiumService (isPremium, hasFeature)
- [x] **Server Management** (Unlimited Servers + Stats) - **1,99€**
- [x] **Docker Compose** (Editor + GitHub) - **1,99€**
- [x] **Knock Knock** - **1,99€**
- [x] **APT Granulaire** - **1,99€**
- [x] **Security Suite** (Reports + Fail2Ban Auto) - **1,99€**
- [x] **Alertes Email** - **1,99€**
- [x] **All Access** - **9,99€**

### knock knock - Intégration détaillée
**Design:** Par serveur (Security tab), pas global

- [x] Script serveur `rise-knock.sh` v2.0.0
- [x] **Generate Sequence** - Générer nouvelle séquence (3-7 knocks)
  - [x] Only when inactive + notification si actif
  - [x] Choix nombre de knocks (slider 3-7)
  - [x] Indicateur couleur (Red=3, Orange=4-5, Green=6-7)
- [x] **Toggle On/Off** - Activer/désactiver knock knock serveur
- [x] **Temporary Off** - Désactiver temporairement (X minutes)
- [x] Client: KnockConfig model + SSH service
- [x] UI: Security panel avec controls knock knock

---

### Email Alerts - Architecture
**Status:** ✅ Terminé (UI + Server + Client)

#### Flux complet:
1. **Settings App** (global): Gestion des credentials SMTP locaux
   - Add/Edit/Delete credentials locally (encrypted in FlutterSecureStorage)
   - Chaque credential a un nom (pour identification)
   - Liste "Saved credentials" pour réutilisation

2. **Server Settings** (per-server, Security tab): Déploiement + Validation
   - Dropdown pour sélectionner un credential sauvegardé
   - "Deploy to this server" → envoie credentials au serveur via SSH
   - Serveur envoie email de validation avec code 6 chiffres (validité 15 min)
   - Client demande le code à l'user
   - Vérification serveur → credential marqué "actif"

3. **Server script** (`rise-alert.sh`):
   - `--configure <json>`: Stocke credentials
   - `--send-validation <email>`: Envoie code
   - `--verify-code <code>`: Valide code
   - `--status`: Retourne état {configured, validated}
   - `--test`: Envoie email test

#### UI:
- App Settings: CRUD credentials + status global
- Server Security tab: Deploy + Validate + Status per server

#### Configuration des alertes (par serveur):
- **Toggle "All"** : Active/désactive TOUTES les alertes
- **Toggle par section** : Active/désactive tous les points de cette section
- **Toggle par point** : Active/désactive un point individuel

**Sections d'alertes :**
- Firewall (connexion suspecte, port scan, règles, Fail2Ban)
- Docker (container down, restart loop, nouveau container)
- Système (CPU/memory/disk, service down)
- SSH/Sécurité (échec login, nouvelle clé, nouvelle IP)
- Updates (security updates, regular updates)

#### Fréquence par section (rate limiting):
- **Selector par section** : "Max 1 email par..."
- **UI** : Spinner 00:00 - 23:59 (rotate up/down) ✅
- **Exemple** : "Je veux max 1 email Docker par 02:45"
- **Stockage** : Par serveur, dans /etc/rise/alert-config.json

---

### Documentation Frontend Client
**Status:** À faire (après tout codé)

- Créer un document détaillé présentant l'UI/UX du client RISE Bare
- Screenshots + description de chaque écran, onglet, bouton, toggle, checkbox, dropdown
- Nécessaire pour présentation aux challengers/partenaires
- Emplacement suggéré : `github/RISE-Bare-Client/docs/FRONTEND_DOC.md`

---

### Email Alerts - OTP Access Recovery
**Status:** Idée future (après email alerts fonctionnel)

- [ ] **Enable OTP email access recovery** (toggle dans server settings)
  - **Prérequis:** Serveur doit avoir au moins 1 credential SMTP validé/actif
  - **Scope:** Permet de récupérer l'accès au serveur via email OTP ?
    - Exemple: Si perte clé SSH, envoyer demande de reset à l'email configuré
    - Génère code temporaire pour SSH backup access
  - **Non encore défini:** Détails exacts du flux
  - **UI:** Toggle dans Security tab du serveur (à côté de Knock Knock)

---

## En attente de test
- [ ] Theme toggle - en attente de test utilisateur
- [ ] Email alerts end-to-end - en attente de test
- [ ] Build complet client

---

## Notes

- GitHub access: ✅ Configuré et fonctionnel
- SSH keys: ✅ Configurées
- Tests serveur: En attente de déploiement RISE Bare sur serveur
- Pour les bugs, utiliser ce format:
  - **Description:** 
  - **Reproduction:** 
  - **Solution proposée:**