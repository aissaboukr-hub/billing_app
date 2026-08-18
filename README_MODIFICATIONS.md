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


## Scanner robuste

- Gestion manuelle du cycle de vie de `mobile_scanner` (`autoStart: false`) pour éviter les blocages après navigation.
- Détection `normal` avec timeout 150 ms pour une meilleure réactivité.
- Formats 1D courants (EAN/UPC/Code 128/39/93/ITF) + QR Code.
- Fenêtre de scan large et horizontale, adaptée aux codes-barres imprimés sur des objets cylindriques.
- Zoom manuel 1x / 1,5x / 2x.
- Redémarrage contrôlé après chaque scan et après retour d'une autre page.
- Aucun retour à la vibration.

La version conserve `mobile_scanner` 5.2.3 afin de limiter les changements de compatibilité. Cette version prend en charge la fenêtre de scan et le contrôle du zoom.
