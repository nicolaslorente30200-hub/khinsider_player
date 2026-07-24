import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import 'album_page.dart';
import 'khinsider.dart';
import 'lecteur.dart';
import 'parcourir.dart';

// Palette reprise de l'interface web
const kBg = Color(0xFF14171C);
const kSurface = Color(0xFF1E232B);
const kSurface2 = Color(0xFF262C36);
const kLine = Color(0xFF313945);
const kText = Color(0xFFE8E4DA);
const kMuted = Color(0xFF8A919C);
const kAmber = Color(0xFFF2A33C);
const kAmberDim = Color(0xFF8A5E24);

/// Numero de compilation, injecte par GitHub Actions (--dart-define).
const String kVersion = String.fromEnvironment('VERSION', defaultValue: 'dev');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      title: 'KHINSIDER·ost',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kAmber,
          surface: kSurface,
          onSurface: kText,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kText,
          elevation: 0,
        ),
      ),
      home: const Accueil(),
    );
  }
}

class Accueil extends StatefulWidget {
  const Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> {
  int _onglet = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: const TextSpan(
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
            tooltip: 'Informations',
            icon: const Icon(Icons.info_outline, color: kAmber),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: kSurface,
                title: const Text('KHINSIDER·ost', style: TextStyle(color: kText)),
                content: const Column(
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
                    child: const Text('Fermer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _onglet,
        children: const [PageNouveautes(), PageParcourir(), PageRecherche()],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MiniLecteur(),
          NavigationBar(
            backgroundColor: kSurface,
            indicatorColor: kAmberDim,
            selectedIndex: _onglet,
            onDestinationSelected: (i) => setState(() => _onglet = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.new_releases_outlined),
                selectedIcon: Icon(Icons.new_releases),
                label: 'Nouveautés',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Parcourir',
              ),
              NavigationDestination(
                icon: Icon(Icons.search),
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
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kLine)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Pochette(url: album?.pochette, taille: 36, titre: album?.titre ?? ''),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: Lecteur.instance.preparation,
                      builder: (context, enPreparation, _) {
                        if (enPreparation) {
                          return ValueListenableBuilder<List<Piste>>(
                            valueListenable: Lecteur.instance.pistesEnFile,
                            builder: (context, enFile, __) {
                              final total = album?.pistes.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Chargement de l\'album…',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: kText, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    total != null
                                        ? '${album!.titre} · ${enFile.length}/$total pistes'
                                        : album?.titre ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: kMuted, fontSize: 11.5),
                                  ),
                                ],
                              );
                            },
                          );
                        }
                        return StreamBuilder<SequenceState?>(
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
                                  style: const TextStyle(
                                      color: kText, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                if (album != null)
                                  Text(
                                    album.titre,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: kMuted, fontSize: 11.5),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: Lecteur.instance.preparation,
                    builder: (context, enPreparation, _) {
                      if (enPreparation) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: kAmber),
                          ),
                        );
                      }
                      return StreamBuilder<PlayerState>(
                        stream: lecteur.playerStateStream,
                        builder: (context, snap) {
                          final enLecture = snap.data?.playing ?? false;
                          return IconButton(
                            icon: Icon(enLecture ? Icons.pause : Icons.play_arrow, color: kAmber),
                            onPressed: enLecture ? lecteur.pause : lecteur.play,
                          );
                        },
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
            return const Center(child: CircularProgressIndicator(color: kAmber));
          }
          if (snap.hasError) {
            return _Erreur(message: '${snap.error}', onRetry: _rafraichir);
          }
          final albums = snap.data ?? [];
          if (albums.isEmpty) {
            return const Center(
              child: Text('Aucune nouveauté trouvée.',
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
            style: const TextStyle(color: kText),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lancer(),
            decoration: InputDecoration(
              hintText: 'Rechercher un jeu, un album…',
              hintStyle: const TextStyle(color: kMuted),
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kLine),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: kAmber),
                onPressed: _lancer,
              ),
            ),
          ),
        ),
        Expanded(
          child: _futur == null
              ? const Center(
                  child: Text('Tape le nom d\'un jeu ou d\'un album.',
                      style: TextStyle(color: kMuted)),
                )
              : FutureBuilder<List<Album>>(
                  future: _futur,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator(color: kAmber));
                    }
                    if (snap.hasError) {
                      return _Erreur(message: '${snap.error}', onRetry: _lancer);
                    }
                    final albums = snap.data ?? [];
                    if (albums.isEmpty) {
                      return const Center(
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
        side: const BorderSide(color: kLine),
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
                      style: const TextStyle(
                        color: kText,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    if (album.infos.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(album.infos,
                          style: const TextStyle(color: kMuted, fontSize: 12.5)),
                    ],
                    if (album.annee.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(album.annee,
                          style: const TextStyle(
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
            const Icon(Icons.cloud_off, color: kMuted, size: 36),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: kAmber,
                side: const BorderSide(color: kAmberDim),
              ),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
