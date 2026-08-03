import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'album_page.dart';
import 'khinsider.dart';
import 'lecteur.dart';
import 'parcourir.dart';

/// Un jeu de couleurs complet. Remplace l'ancien schema de constantes fixes
/// pour permettre un changement de theme en direct (voir PageParametres) :
/// kBg/kAmber/etc. ci-dessous restent le point d'acces utilise partout dans
/// l'app, mais lisent desormais la palette courante plutot qu'une valeur
/// figee a la compilation.
class Palette {
  final String nom;
  final Brightness luminosite;
  final Color fond, surface, surface2, ligne, texte, attenue, accent, accentAttenue;

  const Palette({
    required this.nom,
    required this.luminosite,
    required this.fond,
    required this.surface,
    required this.surface2,
    required this.ligne,
    required this.texte,
    required this.attenue,
    required this.accent,
    required this.accentAttenue,
  });
}

const List<Palette> palettes = [
  Palette(
    nom: 'Ambre (défaut)',
    luminosite: Brightness.dark,
    fond: Color(0xFF14171C),
    surface: Color(0xFF1E232B),
    surface2: Color(0xFF262C36),
    ligne: Color(0xFF313945),
    texte: Color(0xFFE8E4DA),
    attenue: Color(0xFF8A919C),
    accent: Color(0xFFF2A33C),
    accentAttenue: Color(0xFF8A5E24),
  ),
  Palette(
    nom: 'Bleu',
    luminosite: Brightness.dark,
    fond: Color(0xFF10151C),
    surface: Color(0xFF1A222D),
    surface2: Color(0xFF212B38),
    ligne: Color(0xFF2E3A48),
    texte: Color(0xFFE4E9EF),
    attenue: Color(0xFF8996A6),
    accent: Color(0xFF4FA3E3),
    accentAttenue: Color(0xFF2A5A85),
  ),
  Palette(
    nom: 'Vert',
    luminosite: Brightness.dark,
    fond: Color(0xFF121A15),
    surface: Color(0xFF1B261E),
    surface2: Color(0xFF223028),
    ligne: Color(0xFF304038),
    texte: Color(0xFFE3ECE5),
    attenue: Color(0xFF8CA495),
    accent: Color(0xFF5BC286),
    accentAttenue: Color(0xFF2F6B48),
  ),
  Palette(
    nom: 'Clair',
    luminosite: Brightness.light,
    fond: Color(0xFFF7F5F1),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFEBE3),
    ligne: Color(0xFFDAD4C8),
    texte: Color(0xFF201C15),
    attenue: Color(0xFF6B6558),
    accent: Color(0xFFC97A1E),
    accentAttenue: Color(0xFFE7B87A),
  ),
];

const _clePaletteChoisie = 'palette_choisie';

/// Palette active — modifiee depuis PageParametres, persistee dans
/// SharedPreferences, chargee au demarrage dans main() avant runApp().
final ValueNotifier<Palette> paletteNotifier = ValueNotifier<Palette>(palettes.first);

Future<void> chargerPaletteEnregistree() async {
  final prefs = await SharedPreferences.getInstance();
  final nom = prefs.getString(_clePaletteChoisie);
  final trouvee = palettes.where((p) => p.nom == nom).firstOrNull;
  if (trouvee != null) paletteNotifier.value = trouvee;
}

Future<void> choisirPalette(Palette p) async {
  paletteNotifier.value = p;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_clePaletteChoisie, p.nom);
}

// Points d'acces utilises partout dans l'app — plus des constantes figees,
// mais des getters qui refletent la palette courante (voir Palette).
Color get kBg => paletteNotifier.value.fond;
Color get kSurface => paletteNotifier.value.surface;
Color get kSurface2 => paletteNotifier.value.surface2;
Color get kLine => paletteNotifier.value.ligne;
Color get kText => paletteNotifier.value.texte;
Color get kMuted => paletteNotifier.value.attenue;
Color get kAmber => paletteNotifier.value.accent;
Color get kAmberDim => paletteNotifier.value.accentAttenue;

/// Numero de compilation, injecte par GitHub Actions (--dart-define).
const String kVersion = String.fromEnvironment('VERSION', defaultValue: 'dev');

/// Filtre local (sans requete reseau) applique a la page actuellement
/// affichee — ex. PageNouveautes filtre sa liste deja chargee selon ce texte.
final ValueNotifier<String> filtrePage = ValueNotifier<String>('');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await chargerPaletteEnregistree();

  // Active la lecture en arriere-plan et les controles systeme.
  //
  // Attention : androidNotificationOngoing: true impose
  // androidStopForegroundOnPause: true. La combinaison inverse est refusee
  // par audio_service, et l'initialisation echoue alors sans notification
  // ni lecture hors application.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'xyz.perso.khinsider_ost.audio',
      androidNotificationChannelName: 'Lecture',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    );
    etatServiceAudio = 'OK';
  } catch (e, st) {
    etatServiceAudio = 'ECHEC : $e';
    debugPrint('[DIAG_AUDIO] echec init JustAudioBackground: $e');
    debugPrint('[DIAG_AUDIO] stacktrace: $st');
  }
  debugPrint('[DIAG_AUDIO] etatServiceAudio = $etatServiceAudio');

  // Depuis Android 13, la notification du lecteur n'apparait pas sans cette
  // autorisation, et le service au premier plan ne tient pas.
  try {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  } catch (_) {
    // plateforme sans notion de permission : sans consequence
  }

  runApp(const KhApp());
}

class KhApp extends StatelessWidget {
  const KhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Palette>(
      valueListenable: paletteNotifier,
      builder: (context, palette, _) {
        return MaterialApp(
          title: 'KHINSIDER·ost',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: palette.luminosite,
            scaffoldBackgroundColor: palette.fond,
            colorScheme: ColorScheme(
              brightness: palette.luminosite,
              primary: palette.accent,
              onPrimary: palette.fond,
              secondary: palette.accent,
              onSecondary: palette.fond,
              surface: palette.surface,
              onSurface: palette.texte,
              error: const Color(0xFFCF6679),
              onError: palette.fond,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: palette.fond,
              foregroundColor: palette.texte,
              elevation: 0,
            ),
          ),
          home: Accueil(),
        );
      },
    );
  }
}

class Accueil extends StatefulWidget {
  Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  int _onglet = 0;
  bool _rechercheOuverte = false;
  final _controleurFiltre = TextEditingController();

  @override
  void dispose() {
    _controleurFiltre.dispose();
    super.dispose();
  }

  void _fermerRecherche() {
    setState(() => _rechercheOuverte = false);
    _controleurFiltre.clear();
    filtrePage.value = '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _rechercheOuverte
            ? TextField(
                controller: _controleurFiltre,
                autofocus: true,
                style: TextStyle(color: kText),
                decoration: InputDecoration(
                  hintText: 'Filtrer cette page…',
                  hintStyle: TextStyle(color: kMuted),
                  border: InputBorder.none,
                ),
                onChanged: (v) => filtrePage.value = v,
              )
            : RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
            children: [
              TextSpan(text: 'KHINSIDER', style: TextStyle(color: Colors.white)),
              TextSpan(text: '·', style: TextStyle(color: kAmber)),
              TextSpan(text: 'ost', style: TextStyle(color: kMuted)),
              TextSpan(
                  text: '  v$kVersion',
                  style: TextStyle(
                      color: kMuted, fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: _rechercheOuverte ? 'Fermer le filtre' : 'Filtrer cette page',
            icon: Icon(_rechercheOuverte ? Icons.close : Icons.search, color: kAmber),
            onPressed: _rechercheOuverte
                ? _fermerRecherche
                : () => setState(() => _rechercheOuverte = true),
          ),
          IconButton(
            tooltip: 'Informations',
            icon: Icon(Icons.info_outline, color: kAmber),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: kSurface,
                title: Text('KHINSIDER·ost', style: TextStyle(color: kText)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Version $kVersion', style: TextStyle(color: kText)),
                    SizedBox(height: 8),
                    Text('Idée : nIKO', style: TextStyle(color: kText)),
                    Text('Développement : IA (Claude)', style: TextStyle(color: kText)),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Paramètres',
            icon: Icon(Icons.settings_outlined, color: kAmber),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PageParametres()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _onglet,
        children: [PageNouveautes(), PageParcourir(), PageRecherche()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniLecteur(),
          NavigationBar(
            backgroundColor: kSurface,
            indicatorColor: kAmberDim,
            selectedIndex: _onglet,
            onDestinationSelected: (i) {
              if (_rechercheOuverte) _fermerRecherche();
              setState(() => _onglet = i);
            },
            // Couleur explicite sur chaque icone : sans ca, l'icone
            // selectionnee prend une teinte calculee par le theme Material3
            // (onSecondaryContainer), differente du orange exact (kAmber)
            // utilise explicitement partout ailleurs dans l'app.
            destinations: [
              NavigationDestination(
                icon: Icon(Icons.new_releases_outlined, color: kMuted),
                selectedIcon: Icon(Icons.new_releases, color: kAmber),
                label: 'Nouveautés',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined, color: kMuted),
                selectedIcon: Icon(Icons.explore, color: kAmber),
                label: 'Parcourir',
              ),
              NavigationDestination(
                icon: Icon(Icons.search, color: kMuted),
                selectedIcon: Icon(Icons.search, color: kAmber),
                label: 'Recherche',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barre "lecture en cours", visible depuis l'accueil quel que soit l'onglet.
///
/// Sans elle, quitter la page album (bouton retour) faisait perdre tout
/// moyen de revenir au lecteur : ni indication de ce qui joue, ni raccourci
/// pour y retourner.
class _MiniLecteur extends StatelessWidget {
  const _MiniLecteur();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: Lecteur.instance.slugActif,
      builder: (context, slug, _) {
        if (slug == null) return const SizedBox.shrink();
        final album = Lecteur.instance.albumActif;
        final lecteur = Lecteur.instance.player;

        return Material(
          color: kSurface2,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PageAlbum(slug: slug)),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: kLine)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Pochette(url: album?.pochette, taille: 36, titre: album?.titre ?? ''),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StreamBuilder<SequenceState?>(
                      stream: lecteur.sequenceStateStream,
                      builder: (context, snap) {
                        final item = snap.data?.currentSource?.tag as MediaItem?;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item?.title ?? album?.titre ?? '…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: kText, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            if (album != null)
                              Text(
                                album.titre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: kMuted, fontSize: 11.5),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  StreamBuilder<PlayerState>(
                    stream: lecteur.playerStateStream,
                    builder: (context, snap) {
                      final enLecture = snap.data?.playing ?? false;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(enLecture ? Icons.pause : Icons.play_arrow, color: kAmber),
                            onPressed: enLecture ? lecteur.pause : lecteur.play,
                          ),
                          IconButton(
                            tooltip: 'Stop',
                            icon: Icon(Icons.stop, color: kMuted),
                            onPressed: Lecteur.instance.arreter,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Nouveautés

class PageNouveautes extends StatefulWidget {
  const PageNouveautes({super.key});

  @override
  State<PageNouveautes> createState() => _PageNouveautesState();
}

class _PageNouveautesState extends State<PageNouveautes>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Album>> _futur;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _futur = Kh.nouveautes();
  }

  Future<void> _rafraichir() async {
    // setState(() => _futur = ...) renverrait le Future lui-meme (valeur de
    // l'expression d'affectation) : Flutter le detecte, leve une erreur et
    // n'appelle jamais markNeedsBuild, donc rien ne se rafraichit a l'ecran.
    setState(() {
      _futur = Kh.nouveautes();
    });
    await _futur;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _rafraichir,
      color: kAmber,
      backgroundColor: kSurface,
      child: FutureBuilder<List<Album>>(
        future: _futur,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: kAmber));
          }
          if (snap.hasError) {
            return _Erreur(message: '${snap.error}', onRetry: _rafraichir);
          }
          final albums = snap.data ?? [];
          if (albums.isEmpty) {
            return Center(
              child: Text('Aucune nouveauté trouvée.',
                  style: TextStyle(color: kMuted)),
            );
          }
          return ValueListenableBuilder<String>(
            valueListenable: filtrePage,
            builder: (context, filtre, _) {
              final q = filtre.trim().toLowerCase();
              final visibles = q.isEmpty
                  ? albums
                  : albums
                      .where((a) =>
                          a.titre.toLowerCase().contains(q) ||
                          a.infos.toLowerCase().contains(q) ||
                          a.annee.toLowerCase().contains(q))
                      .toList();
              if (visibles.isEmpty) {
                return Center(
                  child: Text('Aucun résultat pour ce filtre.',
                      style: TextStyle(color: kMuted)),
                );
              }

              // Intercale un en-tete de jour avant chaque groupe (comme sur
              // le site web) : Album.jour n'est rempli que sur cette page
              // (section "Latest" de l'accueil khinsider), vide ailleurs.
              final elements = <Object>[];
              String? dernierJour;
              for (final a in visibles) {
                if (a.jour.isNotEmpty && a.jour != dernierJour) {
                  elements.add(a.jour);
                  dernierJour = a.jour;
                }
                elements.add(a);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: elements.length,
                itemBuilder: (_, i) {
                  final e = elements[i];
                  if (e is String) return _EnTeteJour(libelle: e);
                  return CarteAlbum(album: e as Album);
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// En-tete de groupe de jour, style repris de la page web (libelle + trait).
class _EnTeteJour extends StatelessWidget {
  final String libelle;
  const _EnTeteJour({required this.libelle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Row(
        children: [
          Text(
            libelle.toUpperCase(),
            style: TextStyle(
                color: kAmber, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.4),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: kLine, height: 1)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Recherche

class PageRecherche extends StatefulWidget {
  const PageRecherche({super.key});

  @override
  State<PageRecherche> createState() => _PageRechercheState();
}

class _PageRechercheState extends State<PageRecherche>
    with AutomaticKeepAliveClientMixin {
  final _controleur = TextEditingController();
  Future<List<Album>>? _futur;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _lancer() {
    final q = _controleur.text.trim();
    if (q.isEmpty) return;
    // Bloc, pas fleche : "=> _futur = ..." renverrait le Future lui-meme,
    // setState le detecterait comme une erreur et n'appellerait jamais
    // markNeedsBuild — la recherche semblerait alors ne rien faire du tout.
    setState(() {
      _futur = Kh.recherche(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _controleur,
            style: TextStyle(color: kText),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lancer(),
            decoration: InputDecoration(
              hintText: 'Rechercher un jeu, un album…',
              hintStyle: TextStyle(color: kMuted),
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kLine),
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.search, color: kAmber),
                onPressed: _lancer,
              ),
            ),
          ),
        ),
        Expanded(
          child: _futur == null
              ? Center(
                  child: Text('Tape le nom d\'un jeu ou d\'un album.',
                      style: TextStyle(color: kMuted)),
                )
              : FutureBuilder<List<Album>>(
                  future: _futur,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                          child: CircularProgressIndicator(color: kAmber));
                    }
                    if (snap.hasError) {
                      return _Erreur(message: '${snap.error}', onRetry: _lancer);
                    }
                    final albums = snap.data ?? [];
                    if (albums.isEmpty) {
                      return Center(
                        child: Text('Aucun résultat.',
                            style: TextStyle(color: kMuted)),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: albums.length,
                      itemBuilder: (_, i) => CarteAlbum(album: albums[i]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- Widgets communs

class CarteAlbum extends StatelessWidget {
  final Album album;
  const CarteAlbum({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kSurface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PageAlbum(slug: album.slug)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pochette(url: album.pochette, taille: 76, titre: album.titre),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.titre,
                      style: TextStyle(
                        color: kText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (album.infos.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(album.infos,
                          style: TextStyle(color: kMuted, fontSize: 12.5)),
                    ],
                    if (album.annee.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(album.annee,
                          style: TextStyle(
                              color: kAmberDim,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Pochette extends StatelessWidget {
  final String? url;
  final double taille;
  final String titre;

  const Pochette({
    super.key,
    required this.url,
    required this.taille,
    required this.titre,
  });

  @override
  Widget build(BuildContext context) {
    final initiales = titre.isEmpty
        ? '?'
        : titre.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').padRight(2, ' ').substring(0, 2).toUpperCase();

    final repli = Container(
      width: taille,
      height: taille,
      color: kSurface2,
      alignment: Alignment.center,
      child: Text(
        initiales,
        style: TextStyle(
          color: kAmber,
          fontWeight: FontWeight.bold,
          fontSize: taille / 4,
        ),
      ),
    );

    // Une URL mal encodee ferait echouer Image.network avant tout affichage
    final lien = uriSure(url);

    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: lien == null
          ? repli
          : Image.network(
              lien.toString(),
              width: taille,
              height: taille,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => repli,
            ),
    );
  }
}

class _Erreur extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _Erreur({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: kMuted, size: 36),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: kAmber,
                side: BorderSide(color: kAmberDim),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class PageParametres extends StatelessWidget {
  const PageParametres({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('Paramètres', style: TextStyle(color: kText)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text('Thème de couleur',
              style: TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ValueListenableBuilder<Palette>(
            valueListenable: paletteNotifier,
            builder: (context, actuelle, _) {
              return Column(
                children: palettes.map((p) {
                  final selectionnee = p.nom == actuelle.nom;
                  return Card(
                    color: kSurface,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: selectionnee ? kAmber : kLine),
                    ),
                    child: ListTile(
                      onTap: () => choisirPalette(p),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _pastilleCouleur(p.accent),
                          const SizedBox(width: 4),
                          _pastilleCouleur(p.fond),
                        ],
                      ),
                      title: Text(p.nom, style: TextStyle(color: kText)),
                      trailing: selectionnee
                          ? Icon(Icons.check_circle, color: kAmber)
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pastilleCouleur(Color c) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
  }
}
