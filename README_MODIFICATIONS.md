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
- Format d’import strict : exactement 4 colonnes, dans cet ordre : `Code-barres 1`, `Code-barres 2`, `Nom`, `Prix`. Aucune autre colonne n’est autorisée. `Code-barres 2` est facultatif. Le stock est initialisé à 0.
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


## 6. Authentification par nom d'utilisateur et rôles
- Connexion avec le **nom d'utilisateur** à la place de l'adresse e-mail.
- Premier compte créé : **Administrateur**.
- Comptes suivants : **Utilisateur** par défaut.
- Administrateur : accès complet à l'application et gestion des utilisateurs, rôles et mots de passe.
- Utilisateur : accès aux fonctions de caisse, scanner, retours et historique, mais **sans accès** à :
  - Gestion des produits.
  - Informations du commerce.
  - Import / Export.
  - Configuration URL Google Sheets.
- Les routes protégées sont également contrôlées côté navigation (`GoRouter`) : un utilisateur ne peut pas contourner la restriction en ouvrant directement une URL.
- Migration prévue pour les anciens comptes : leur ancien e-mail est converti en nom d'utilisateur avec la partie avant `@` lors de la première connexion.
