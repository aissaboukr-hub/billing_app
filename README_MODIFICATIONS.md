# Modifications intégrées

## 1. Français et Dinar algérien
- Interface principale et messages utilisateurs traduits en français.
- Format monétaire centralisé avec `fr_DZ` et `DA`.
- QR de paiement modifié de INR vers DZD.

## 2. Authentification
- Écran Connexion / Inscription.
- Mot de passe d'au moins 8 caractères.
- Les mots de passe sont stockés sous forme de hash SHA-256 avec sel aléatoire, jamais en clair.
- Session locale Hive et redirection vers `/login` si l'utilisateur n'est pas connecté.
- Pour un déploiement multi-utilisateurs/production, remplacer cette authentification locale par Firebase Auth, Supabase Auth ou un backend sécurisé.

## 3. Import produits
- Excel `.xlsx` et `.xls` avec `excel_community`.
- Détection des colonnes Désignation/Nom, Code-barres, Prix et Stock.
- Import Google Sheets via lien public/accessible en lecture (export CSV Google Visualization).

## 4. Export ventes
- Export Excel de la vente courante.
- Export Google Sheets via Google Apps Script.
- Script prêt à déployer : `google_apps_script/Code.gs`.
- Configurer l'URL `/exec` dans Paramètres > Données > URL Google Sheets.

## 5. Scanner
- `DetectionSpeed.noDuplicates` pour éviter les lectures répétées et réduire le travail inutile.
- Flash disponible.
- Le contrôleur est réutilisé et arrêté pendant les écrans secondaires.

## Installation

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Le SDK Flutter n'est pas installé dans l'environnement qui a préparé cette archive ; une validation finale doit donc être faite dans ton environnement Flutter/Codemagic.

## 6. Corrections qualité de code (revue du 19/08/2026)

### Bugs critiques corrigés
- **`lib/core/service_locator.dart` ne compilait pas** : tous les imports relatifs avaient un `../` de trop (`../../features/...` au lieu de `../features/...`). Ce fichier initialise l'injection de dépendances utilisée par `main.dart` — l'app entière était donc cassée à la compilation. Même problème corrigé dans `lib/features/history/data/history_service.dart`. Les 119 imports relatifs du projet ont été vérifiés systématiquement.
- **Erreurs d'impression invisibles** : sur l'écran de paiement (`checkout_page.dart`), une erreur du `BillingBloc` (imprimante non connectée, échec d'impression) n'était affichée nulle part dans l'UI. Le listener écoute maintenant `state.error`.
- **Encodage des tickets imprimés** : `printer_helper.dart` convertissait le texte en octets via `codeUnits` (UTF-16), ce qui aurait corrompu les caractères accentués français (é, à, ç…) sur une vraie imprimante thermique ESC/POS. Remplacé par un encodage Latin-1 avec repli sûr sur les caractères hors plage.

### Qualité / cohérence
- `ProductState.copyWith` avait un comportement ambigu avec des commentaires d'hésitation laissés dans le code. Remplacé par un pattern explicite `clearMessage`, cohérent avec le pattern `clearError` déjà utilisé dans `BillingState`.
- `AuthService` était instancié directement (`AuthService()`) à 3 endroits (routeur, page de connexion, paramètres) au lieu de passer par `get_it`, incohérent avec le reste de l'architecture. Il est maintenant enregistré dans `service_locator.dart` et injecté partout via `di.sl<AuthService>()`.
- Nettoyage de commentaires de « réflexion à voix haute » laissés dans `printer_helper.dart` (hésitations sur le choix de package).

### Tests
- `test/widget_test.dart` (test par défaut du compteur Flutter, ne compilait même pas avec la vraie `MyApp`) a été supprimé et remplacé par de vrais tests unitaires sur la logique métier, sans dépendance aux plugins natifs :
  - `test/features/auth/auth_service_test.dart` — inscription, connexion, mot de passe incorrect, email dupliqué, hash jamais stocké en clair, déconnexion (Hive en mémoire temporaire).
  - `test/features/billing/billing_bloc_test.dart` — ajout au panier, fusion de quantités, code-barres inconnu, suppression, vidage du panier, calcul du total (avec un `FakeProductRepository` en mémoire).
  - `test/features/product/product_state_test.dart` — sémantique de `copyWith`/`clearMessage`.
- Ajout de `bloc_test: ^9.1.7` en `dev_dependencies` (nécessaire pour `billing_bloc_test.dart`) — pense à lancer `flutter pub get` avant `flutter test`.

