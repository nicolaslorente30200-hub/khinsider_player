import 'package:flutter/material.dart';

import 'khinsider.dart';
import 'main.dart';

/// Onglet "Parcourir" : classements, plateformes, annees — repris de la
/// navigation de la version web du site.
///
/// Deux ecarts volontaires par rapport a la version web : pas de navigation
/// par lettre (A-Z) ni par type (gamerips, OST, singles...), jugees moins
/// utiles que les trois sections ci-dessous.
class PageParcourir extends StatelessWidget {
  const PageParcourir({super.key});

  static const List<({String libelle, String chemin})> _classements = [
    (libelle: 'Top 40', chemin: '/top40'),
    (libelle: 'Top 1000 (all time)', chemin: '/all-time-top-100'),
    (libelle: 'Top 100 (6 derniers mois)', chemin: '/last-6-months-top-100'),
    (libelle: 'Top 100 (nouveautés)', chemin: '/top-100-newly-added'),
    (libelle: 'Les plus consultés', chemin: '/currently-viewed'),
    (libelle: 'Les plus mis en favori', chemin: '/most-favorites'),
  ];

  static const List<({String libelle, String slug})> _plateformes = [
    (libelle: 'NES', slug: 'nintendo-nes'),
    (libelle: 'SNES', slug: 'nintendo-snes'),
    (libelle: 'Nintendo 64', slug: 'nintendo-64'),
    (libelle: 'GameCube', slug: 'nintendo-gamecube'),
    (libelle: 'Wii', slug: 'nintendo-wii'),
    (libelle: 'Wii U', slug: 'nintendo-wii-u'),
    (libelle: 'Switch', slug: 'nintendo-switch'),
    (libelle: 'Switch 2', slug: 'switch-2'),
    (libelle: 'Game Boy', slug: 'gameboy'),
    (libelle: 'Game Boy Advance', slug: 'gameboy-advance'),
    (libelle: 'Nintendo DS', slug: 'nintendo-ds'),
    (libelle: 'Nintendo 3DS', slug: 'nintendo-3ds'),
    (libelle: 'PlayStation', slug: 'playstation'),
    (libelle: 'PlayStation 2', slug: 'playstation-2'),
    (libelle: 'PlayStation 3', slug: 'playstation-3'),
    (libelle: 'PlayStation 4', slug: 'playstation-4'),
    (libelle: 'PlayStation 5', slug: 'playstation-5'),
    (libelle: 'PSP', slug: 'playstation-portable-psp'),
    (libelle: 'PS Vita', slug: 'playstation-vita'),
    (libelle: 'Steam', slug: 'steam'),
    (libelle: 'Windows', slug: 'windows'),
    (libelle: 'Xbox', slug: 'xbox'),
    (libelle: 'Xbox 360', slug: 'xbox-360'),
    (libelle: 'Xbox One', slug: 'xbox-one'),
    (libelle: 'Xbox Series X', slug: 'xbox-series-x'),
    (libelle: 'Mega Drive / Genesis', slug: 'sega-mega-drive-genesis'),
    (libelle: 'Dreamcast', slug: 'sega-dreamcast'),
    (libelle: 'Arcade', slug: 'arcade'),
    (libelle: 'Android', slug: 'android'),
    (libelle: 'iOS', slug: 'ios'),
    (libelle: 'macOS', slug: 'mac-os'),
    (libelle: 'Linux', slug: 'linux'),
  ];

  /// /console-list melange plateformes et navigation par type sous la meme
  /// forme d'URL (/game-soundtracks/<slug>) : ecarte volontairement, comme
  /// la navigation par lettre, dans la version web.
  static const Set<String> _typesExclus = {
    '/game-soundtracks/gamerips',
    '/game-soundtracks/ost', // "Soundtracks"
    '/game-soundtracks/singles',
    '/game-soundtracks/arrangements',
    '/game-soundtracks/remixes',
    '/game-soundtracks/compilations',
    '/game-soundtracks/inspired-by',
  };

  @override
  Widget build(BuildContext context) {
    final anneeCourante = DateTime.now().year;
    final annees = List.generate(16, (i) => anneeCourante - i);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _section('Classements', [
          for (final c in _classements)
            _Pastille(
              libelle: c.libelle,
              onTap: () => _ouvrirListe(context, c.libelle, c.chemin),
            ),
          _Pastille(
            libelle: 'Albums au hasard',
            icone: Icons.shuffle,
            onTap: () => _albumAuHasard(context),
          ),
          _Pastille(
            libelle: 'Tirage filtré',
            icone: Icons.tune,
            onTap: () => _ouvrirRequeteur(context),
          ),
        ]),
        const SizedBox(height: 24),
        _section('Plateformes', [
          for (final p in _plateformes)
            _Pastille(
              libelle: p.libelle,
              onTap: () => _ouvrirListe(
                  context, p.libelle, '/game-soundtracks/${p.slug}'),
            ),
          _Pastille(
            libelle: 'Toutes',
            icone: Icons.apps,
            onTap: () => _ouvrirIndex(
              context,
              'Plateformes',
              '/console-list',
              RegExp(r'^/game-soundtracks/[a-z0-9-]+$'),
              exclure: _typesExclus,
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _section('Par année', [
          for (final a in annees)
            _Pastille(
              libelle: '$a',
              onTap: () => _ouvrirListe(
                  context, '$a', '/game-soundtracks/year/$a'),
            ),
          _Pastille(
            libelle: 'Toutes',
            icone: Icons.apps,
            onTap: () => _ouvrirIndex(
              context,
              'Années',
              '/album-years',
              RegExp(r'^/game-soundtracks/year/(19|20)\d{2}$'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _section(String titre, List<Widget> pastilles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre,
          style: TextStyle(
              color: kText, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: pastilles),
      ],
    );
  }

  void _ouvrirListe(BuildContext context, String titre, String chemin) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageListeAlbums(titre: titre, chemin: chemin),
    ));
  }

  void _ouvrirIndex(
      BuildContext context, String titre, String chemin, RegExp motif,
      {Set<String> exclure = const {}}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageIndexParcourir(
          titre: titre, chemin: chemin, motif: motif, exclure: exclure),
    ));
  }

  /// Plutot qu'un seul album (l'ancien comportement, via /random-album),
  /// tire [nombre] albums independamment au hasard (meme mecanisme, repete)
  /// pour naviguer dans une liste — sujet a retirage a chaque "Reessayer"
  /// grace a PageListeAlbums.chargeur.
  Future<List<Album>> _tirageAuHasard({int nombre = 10}) async {
    final slugs = <String>{};
    while (slugs.length < nombre) {
      slugs.add(await Kh.albumAuHasard());
    }
    final details = await Future.wait(slugs.map(Kh.album));
    return [
      for (final d in details)
        Album(
          slug: d.slug,
          titre: d.titre,
          pochette: d.pochette,
          infos: d.infos,
          annee: d.annee,
        ),
    ];
  }

  void _albumAuHasard(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageListeAlbums(
        titre: 'Au hasard',
        chemin: '',
        chargeur: _tirageAuHasard,
      ),
    ));
  }

  /// Tirage au hasard restreint a des plateformes et/ou annees choisies. Sans
  /// aucun critere, retombe sur _tirageAuHasard (hasard pur, tout le site).
  /// Avec des plateformes : recupere leurs listes completes, filtrees par
  /// annee si des annees sont aussi choisies (les pages de plateforme
  /// donnent deja l'annee par album, pas besoin d'appel supplementaire).
  /// Avec seulement des annees : recupere les pages d'annee correspondantes.
  /// [cheminsPlateformes]/[cheminsAnnees] : chemins complets (/game-
  /// soundtracks/...), pas de simples slugs — ils viennent tels quels de
  /// Kh.liensIndex (meme source que le bouton "Toutes" de Parcourir), pour
  /// couvrir la liste reelle et complete du site, pas une liste figee.
  Future<List<Album>> _tirageFiltre({
    required List<String> cheminsPlateformes,
    required List<String> cheminsAnnees,
    required int nombre,
  }) async {
    List<Album> bassin;

    if (cheminsPlateformes.isNotEmpty) {
      final listes = await Future.wait(cheminsPlateformes.map(Kh.liste));
      bassin = listes.expand((l) => l).toList();
      if (cheminsAnnees.isNotEmpty) {
        final anneesTexte = cheminsAnnees
            .map((c) => RegExp(r'(\d{4})$').firstMatch(c)?.group(1))
            .whereType<String>()
            .toSet();
        bassin = bassin.where((a) => anneesTexte.contains(a.annee)).toList();
      }
    } else if (cheminsAnnees.isNotEmpty) {
      final listes = await Future.wait(cheminsAnnees.map(Kh.liste));
      bassin = listes.expand((l) => l).toList();
    } else {
      return _tirageAuHasard(nombre: nombre);
    }

    final vus = <String>{};
    bassin = bassin.where((a) => vus.add(a.slug)).toList();
    bassin.shuffle();
    return bassin.take(nombre).toList();
  }

  void _ouvrirRequeteur(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageRequeteur(tirage: _tirageFiltre),
    ));
  }
}

/// Page complete (pas une fenetre modale : trop de plateformes/annees pour
/// rester confortable en modal) pour choisir plateformes, annees et nombre
/// d'albums avant un tirage au hasard filtre.
class PageRequeteur extends StatefulWidget {
  final Future<List<Album>> Function({
    required List<String> cheminsPlateformes,
    required List<String> cheminsAnnees,
    required int nombre,
  }) tirage;

  const PageRequeteur({super.key, required this.tirage});

  @override
  State<PageRequeteur> createState() => _PageRequeteurState();
}

class _PageRequeteurState extends State<PageRequeteur> {
  static const _typesExclus = PageParcourir._typesExclus;

  late Future<List<List<LienIndex>>> _futur;
  final _cheminsPlateformesChoisis = <String>{};
  final _cheminsAnneesChoisis = <String>{};
  final _controleurNombre = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _futur = Future.wait([
      Kh.liensIndex(
        '/console-list',
        RegExp(r'^/game-soundtracks/[a-z0-9-]+$'),
        exclure: _typesExclus,
      ),
      Kh.liensIndex(
        '/album-years',
        RegExp(r'^/game-soundtracks/year/(19|20)\d{2}$'),
      ),
    ]);
  }

  @override
  void dispose() {
    _controleurNombre.dispose();
    super.dispose();
  }

  void _lancer() {
    final nombre = int.tryParse(_controleurNombre.text.trim()) ?? 10;
    final cheminsPlateformes = _cheminsPlateformesChoisis.toList();
    final cheminsAnnees = _cheminsAnneesChoisis.toList();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageListeAlbums(
        titre: 'Tirage filtré',
        chemin: '',
        chargeur: () => widget.tirage(
          cheminsPlateformes: cheminsPlateformes,
          cheminsAnnees: cheminsAnnees,
          nombre: nombre,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tirage filtré'),
        actions: [
          IconButton(
            tooltip: 'Lancer',
            icon: Icon(Icons.shuffle, color: kAmber),
            onPressed: _lancer,
          ),
        ],
      ),
      body: FutureBuilder<List<List<LienIndex>>>(
        future: _futur,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: kAmber));
          }
          if (snap.hasError) {
            return Center(
              child: Text('${snap.error}', style: TextStyle(color: kMuted)),
            );
          }
          final plateformesDispo = snap.data![0];
          final anneesDispo = snap.data![1];

          return ListView(
            // Marge basse dynamique : sans elle, les derniers elements se
            // retrouvent caches sous la barre de navigation systeme, cette
            // page n'ayant pas de bottomNavigationBar pour la reserver.
            padding: EdgeInsets.fromLTRB(
                14, 14, 14, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              TextField(
                controller: _controleurNombre,
                keyboardType: TextInputType.number,
                style: TextStyle(color: kText),
                decoration: const InputDecoration(labelText: "Nombre d'albums"),
              ),
              const SizedBox(height: 20),
              Text('Plateformes (optionnel, ${plateformesDispo.length})',
                  style: TextStyle(
                      color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in plateformesDispo)
                    FilterChip(
                      label: Text(p.libelle),
                      selected: _cheminsPlateformesChoisis.contains(p.chemin),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _cheminsPlateformesChoisis.add(p.chemin);
                        } else {
                          _cheminsPlateformesChoisis.remove(p.chemin);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Années (optionnel, ${anneesDispo.length})',
                  style: TextStyle(
                      color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in anneesDispo)
                    FilterChip(
                      label: Text(a.libelle),
                      selected: _cheminsAnneesChoisis.contains(a.chemin),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _cheminsAnneesChoisis.add(a.chemin);
                        } else {
                          _cheminsAnneesChoisis.remove(a.chemin);
                        }
                      }),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Pastille cliquable, style commun aux trois sections et aux pages d'index.
class _Pastille extends StatelessWidget {
  final String libelle;
  final IconData? icone;
  final VoidCallback onTap;

  const _Pastille({required this.libelle, this.icone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 15, color: kAmber),
              const SizedBox(width: 6),
            ],
            Text(libelle, style: TextStyle(color: kText, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Page de liste d'albums : classement, plateforme ou annee. Meme rendu que
/// les onglets Nouveautes/Recherche (CarteAlbum dans un ListView.builder,
/// deja paresseux — pas besoin de pagination manuelle meme sur les grosses
/// plateformes qui renvoient plusieurs centaines d'albums).
class PageListeAlbums extends StatefulWidget {
  final String titre;
  final String chemin;

  /// Source alternative a Kh.liste(chemin) — utilise par ex. par "Album au
  /// hasard" pour afficher un tirage local plutot qu'une page du site.
  final Future<List<Album>> Function()? chargeur;

  const PageListeAlbums({
    super.key,
    required this.titre,
    required this.chemin,
    this.chargeur,
  });

  @override
  State<PageListeAlbums> createState() => _PageListeAlbumsState();
}

class _PageListeAlbumsState extends State<PageListeAlbums> {
  late Future<List<Album>> _futur;

  Future<List<Album>> _charger() =>
      widget.chargeur != null ? widget.chargeur!() : Kh.liste(widget.chemin);

  @override
  void initState() {
    super.initState();
    _futur = _charger();
  }

  void _reessayer() {
    // Bloc, pas fleche : "=> _futur = ..." renverrait le Future lui-meme et
    // setState n'appellerait jamais markNeedsBuild (voir _lancer dans
    // main.dart pour le meme piege deja rencontre sur la recherche).
    setState(() {
      _futur = _charger();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: FutureBuilder<List<Album>>(
        future: _futur,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: kAmber));
          }
          if (snap.hasError) {
            return _erreur('${snap.error}');
          }
          final albums = snap.data ?? [];
          if (albums.isEmpty) {
            return Center(
              child: Text('Aucun album trouvé.', style: TextStyle(color: kMuted)),
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

  Widget _erreur(String message) {
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
              onPressed: _reessayer,
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

/// Page d'index (/console-list, /album-years) : pas d'albums a afficher
/// directement, mais des liens vers d'autres sections, en pastilles.
class PageIndexParcourir extends StatefulWidget {
  final String titre;
  final String chemin;
  final RegExp motif;
  final Set<String> exclure;

  const PageIndexParcourir({
    super.key,
    required this.titre,
    required this.chemin,
    required this.motif,
    this.exclure = const {},
  });

  @override
  State<PageIndexParcourir> createState() => _PageIndexParcourirState();
}

class _PageIndexParcourirState extends State<PageIndexParcourir> {
  late Future<List<LienIndex>> _futur;

  @override
  void initState() {
    super.initState();
    _futur = Kh.liensIndex(widget.chemin, widget.motif, exclure: widget.exclure);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: FutureBuilder<List<LienIndex>>(
        future: _futur,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: kAmber));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kMuted, fontSize: 13)),
              ),
            );
          }
          final liens = snap.data ?? [];
          if (liens.isEmpty) {
            return Center(
              child: Text('Rien trouvé.', style: TextStyle(color: kMuted)),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in liens)
                  _Pastille(
                    libelle: l.libelle,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PageListeAlbums(titre: l.libelle, chemin: l.chemin),
                    )),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
