# khinsider_player

Lecteur Android non officiel pour les soundtracks de jeux vidéo de [KHInsider](https://downloads.khinsider.com) : nouveautés, recherche et lecture en arrière-plan. Écrit en Flutter, usage personnel.

## Fonctionnalités

- Parcours des nouveautés, classements, plateformes et années
- Recherche d'un jeu et lecture de sa bande originale
- Lecture en arrière-plan avec notification média (Android 13+)
- Cast direct vers Kodi via JSON-RPC (configuration adresse/port dans les paramètres)

## Développement

```bash
flutter pub get
flutter run
```

Le workflow GitHub Actions (`.github/workflows/build.yml`) compile un APK release à la demande (onglet Actions → "Run workflow").
