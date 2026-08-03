import 'dart:io';

import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;

/// Acces au site, calque sur Khinsider Ripper (projet de 2023 toujours
/// fonctionnel) : requetes nues, sans aucun en-tete personnalise.
///
/// Lecon apprise a nos depens : se faire passer pour Chrome (User-Agent
/// mensonger, en-tetes Sec-Fetch, cookies Cloudflare renvoyes) declenche la
/// protection anti-bot. Un client honnete et discret passe sans probleme.
const String khBase = 'https://downloads.khinsider.com';

final RegExp _reAudio = RegExp(r'\.(mp3|flac|ogg|m4a)$', caseSensitive: false);
final RegExp _reSlug = RegExp(r'/game-soundtracks/album/([^/?#]+)');
final RegExp _reAnnee = RegExp(r'^(19|20)\d{2}$');
final RegExp _reDuree = RegExp(r'^\d+:\d{2}$');
/// Libelles d'icones Material presents dans certaines cellules
/// (le lien de telechargement affiche par exemple "get_app").
bool _estIcone(String t) =>
    t.contains('_') ||
    const {'download', 'play', 'flac', 'mp3', 'ogg'}.contains(t.toLowerCase());

final RegExp _reTaille = RegExp(r'^\d+([.,]\d+)?\s*(o|B|Ko|KB|Mo|MB|Go|GB)$',
    caseSensitive: false);

/// Colonnes de rang/tendance des pages de classement (Top 40, etc.) : un
/// numero de rang nu ("5", "5.") ou un ligature d'icone Material ("remove",
/// "arrow_drop_up", parfois suivie d'un delta "arrow_drop_up+2"). Absentes
/// des pages standard (accueil, recherche), donc sans effet ailleurs.
final RegExp _reRangNombre = RegExp(r'^\d+\.?$');
final RegExp _reRangIcone = RegExp(r'^[a-z_]+([+-]\d+)?$');

/// Un % non suivi de deux chiffres hexadecimaux rend l'URI illegale pour Dart
/// (contrairement a PHP, tolerant). On le neutralise en %25.
final RegExp _rePourcentInvalide = RegExp(r'%(?![0-9A-Fa-f]{2})');

const List<String> _moisFr = [
  '', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const Map<String, int> _moisAnglaisVersNumero = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
  'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11,
  'december': 12,
};
final RegExp _reDateJour = RegExp(r'^([A-Za-z]+)\s+(\d{1,2})\w{0,2},?\s+(\d{4})$');

/// "July 18th, 2026" (texte du <h3> qui precede chaque groupe d'albums sur
/// la page d'accueil) -> "18 juillet 2026", avec "— Aujourd'hui" si la date
/// correspond au jour courant. Chaine d'origine inchangee si non reconnue.
String formaterJourAlbum(String brut) {
  final m = _reDateJour.firstMatch(brut.trim());
  if (m == null) return brut.trim();
  final numeroMois = _moisAnglaisVersNumero[m.group(1)!.toLowerCase()];
  if (numeroMois == null) return brut.trim();
  final jour = int.parse(m.group(2)!);
  final annee = int.parse(m.group(3)!);

  var label = '$jour ${_moisFr[numeroMois]} $annee';
  final maintenant = DateTime.now();
  if (jour == maintenant.day &&
      numeroMois == maintenant.month &&
      annee == maintenant.year) {
    label += " — Aujourd'hui";
  }
  return label;
}

String assainir(String s) => s.replaceAll(_rePourcentInvalide, '%25');

/// Chemin d'une URL, sans exception meme si l'encodage est douteux.
String cheminSur(String href) {
  final propre = assainir(href);
  try {
    final u = Uri.tryParse(propre);
    if (u != null && u.path.isNotEmpty) return u.path;
  } catch (_) {
    // on retombe sur le decoupage manuel
  }
  return propre.split('#').first.split('?').first;
}

/// Normalise un chemin sur-encode : certains liens de khinsider contiennent
/// %2520 (soit %20 encode une seconde fois). On decode jusqu'a stabilisation,
/// puis on reencode proprement chaque segment.
String normaliserChemin(String chemin) {
  var brut = chemin;
  for (var i = 0; i < 4; i++) {
    String d;
    try {
      d = Uri.decodeComponent(assainir(brut));
    } catch (_) {
      break;
    }
    if (d == brut) break;
    brut = d;
  }
  return brut
      .split('/')
      .map((seg) => seg.isEmpty ? seg : Uri.encodeComponent(seg))
      .join('/');
}

/// Uri utilisable, ou null. Force le decodage du chemin pour lever ici
/// plutot qu'au moment de l'affichage ou de la lecture.
Uri? uriSure(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final u = Uri.tryParse(assainir(s));
    if (u == null) return null;
    u.path;
    return u;
  } catch (_) {
    return null;
  }
}

class Album {
  final String slug; // segment d'URL, conserve tel quel
  final String titre;
  final String? pochette;
  final String infos;
  final String annee;

  /// Groupe de date ("18 juillet 2026", "... — Aujourd'hui") — seulement
  /// rempli sur la page d'accueil (section "Latest"), vide ailleurs (liste,
  /// recherche...) faute de balise <h3> de date a proximite.
  final String jour;

  Album({
    required this.slug,
    required this.titre,
    this.pochette,
    this.infos = '',
    this.annee = '',
    this.jour = '',
  });
}

class Piste {
  final String nom;
  final String chemin; // href tel qu'il figure dans la page
  final String duree;
  String? url;

  Piste({required this.nom, required this.chemin, this.duree = ''});
}

/// Lien vers une autre section, trouve sur une page d'index (ex :
/// /console-list, /album-years) plutot que sur une page de liste d'albums.
class LienIndex {
  final String libelle;
  final String chemin;

  LienIndex({required this.libelle, required this.chemin});
}

class AlbumDetail {
  final String slug;
  final String titre;
  final String? pochette;
  final String infos;
  final String annee;
  final List<Piste> pistes;

  /// Bloc "Platforms / Year / Developed by / ..." de la page album, mis en
  /// forme pour affichage — equivalent de la description du site web.
  final String description;

  /// Section "People who viewed this also viewed" de la page album.
  final List<Album> similaires;

  AlbumDetail({
    required this.slug,
    required this.titre,
    this.pochette,
    this.infos = '',
    this.annee = '',
    required this.pistes,
    this.description = '',
    this.similaires = const [],
  });
}

class Kh {
  /// Client unique et persistant, sauf recreation ponctuelle (voir _get).
  ///
  /// Ouvrir une connexion par requete provoquait une resolution DNS a chaque
  /// fois ; sous charge (flux audio en cours), Android finit par repondre
  /// "Failed host lookup". Un client partage reutilise connexion et DNS.
  static http.Client _client = http.Client();

  /// Requete nue, comme Khinsider Ripper : aucun en-tete ajoute.
  ///
  /// Avec reprises espacees : le site limite le debit quand on enchaine les
  /// pages de pistes, et repond alors par une erreur au lieu du contenu.
  static Future<String> _get(String url, {String attendu = '', int essais = 4}) async {
    final propre = assainir(url);
    Object derniere = Exception('echec inconnu');

    for (var i = 0; i < essais; i++) {
      if (i > 0) {
        // Attente croissante : 1 s, 3 s, 6 s — laisse le temps au DNS
        await Future.delayed(Duration(seconds: [0, 1, 3, 6][i.clamp(0, 3)]));
      }

      try {
        final rep = await _client
            .get(Uri.parse(propre))
            .timeout(const Duration(seconds: 25));

        if (rep.statusCode == 200) return rep.body;

        final corps = rep.body.toLowerCase();
        final cloudflare = corps.contains('cloudflare') ||
            corps.contains('attention required') ||
            corps.contains('cf-ray');

        derniere = Exception(cloudflare
            ? 'HTTP ${rep.statusCode} (Cloudflare)'
            : 'HTTP ${rep.statusCode}');

        // Inutile d'insister si la page n'existe pas
        if (rep.statusCode == 404) break;
      } catch (e) {
        derniere = e;

        // Une resolution DNS ratee (reveil de veille, bascule reseau...)
        // laisse parfois le client HTTP bloque de facon permanente meme
        // quand le DNS systeme fonctionne de nouveau : sans recreation,
        // toutes les tentatives suivantes, et toutes les requetes futures,
        // echouent pour la meme raison — c'est ce qui coupait la lecture
        // en cours de route sans que rien ne la relance jamais.
        if (e is SocketException ||
            e.toString().contains('Failed host lookup')) {
          _client.close();
          _client = http.Client();
        }
      }
    }

    throw derniere;
  }

  /// Extrait les albums d'un tableau (accueil, recherche).
  ///
  /// Sur l'accueil (section "Latest"), chaque groupe d'albums est precede
  /// d'un <h3> de date ("July 18th, 2026") — absent des autres pages
  /// (recherche, listes). querySelectorAll('h3, tr') les renvoie dans
  /// l'ordre du document, ce qui permet de suivre le dernier <h3> vu et de
  /// l'attacher a chaque <tr> suivant, sans devoir remonter l'arbre DOM.
  static List<Album> _albumsDepuis(String corps) {
    final doc = parser.parse(corps);
    final vus = <String>{};
    final out = <Album>[];
    String jourActuel = '';

    for (final el in doc.querySelectorAll('h3, tr')) {
      if (el.localName == 'h3') {
        jourActuel = formaterJourAlbum(el.text);
        continue;
      }
      final tr = el;
      String slug = '';
      String nom = '';

      for (final a in tr.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        if (!href.contains('/game-soundtracks/album/')) continue;
        if (_reAudio.hasMatch(href)) continue;
        final m = _reSlug.firstMatch(href);
        if (m == null) continue;
        slug = m.group(1)!; // conserve brut, comme le ripper
        final t = a.text.trim();
        if (t.length > nom.length) nom = t;
      }

      if (slug.isEmpty || nom.isEmpty || !vus.add(slug)) continue;

      final img = tr.querySelector('img');
      final brut = img?.attributes['src'];
      // Les vignettes de liste vivent dans un sous-dossier /thumbs_small/ :
      // la meme image en taille normale existe au meme chemin, ce dossier
      // en moins — sans ca, les listes affichent une image nettement plus
      // petite que la page album, floue une fois agrandie a l'affichage.
      final pochette = brut == null
          ? null
          : assainir(brut.replaceFirst('/thumbs_small/', '/'));

      final meta = <String>[];
      String annee = '';
      for (final td in tr.children.where((e) => e.localName == 'td')) {
        final t = td.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isEmpty || t == nom || t.contains(nom)) continue;
        if (_reAnnee.hasMatch(t)) {
          annee = t;
          continue;
        }
        if (_reRangNombre.hasMatch(t) || _reRangIcone.hasMatch(t)) continue;
        meta.add(t);
      }

      out.add(Album(
        slug: slug,
        titre: nom.replaceAll('&amp;', '&'),
        pochette: pochette,
        infos: meta.take(3).join(' · '),
        annee: annee,
        jour: jourActuel,
      ));
    }
    return out;
  }

  /// Nouveautes : tableau de la page d'accueil.
  static Future<List<Album>> nouveautes() async {
    return _albumsDepuis(await _get('$khBase/'));
  }

  /// Recherche dans la base complete.
  static Future<List<Album>> recherche(String q) async {
    return _albumsDepuis(await _get('$khBase/search?search=${Uri.encodeFull(q)}'));
  }

  /// Page de liste d'albums : classement, plateforme, annee... Meme
  /// structure de tableau que l'accueil et la recherche, donc meme analyse.
  static Future<List<Album>> liste(String chemin) async {
    return _albumsDepuis(await _get('$khBase$chemin'));
  }

  /// Page d'index (/console-list, /album-years) : pas d'albums, mais des
  /// liens vers d'autres sections. [motif] filtre les chemins reconnus,
  /// pour ecarter les liens du menu du site (forums, etc.). [exclure] retire
  /// des chemins precis : /console-list melange plateformes et types
  /// (gamerips, singles...) sous la meme forme d'URL, indiscernables par
  /// [motif] seul — types volontairement ecartes, comme dans la version web.
  static Future<List<LienIndex>> liensIndex(
    String chemin,
    RegExp motif, {
    Set<String> exclure = const {},
  }) async {
    final corps = await _get('$khBase$chemin');
    final doc = parser.parse(corps);
    final vus = <String>{};
    final out = <LienIndex>[];

    for (final a in doc.querySelectorAll('a')) {
      final c = cheminSur(a.attributes['href'] ?? '');
      if (!motif.hasMatch(c) || exclure.contains(c) || !vus.add(c)) continue;

      final texte = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (texte.isEmpty) continue;

      out.add(LienIndex(libelle: texte, chemin: c));
    }
    return out;
  }

  /// Dernier slug tire par [albumAuHasard], pour eviter de retomber sur le
  /// meme album deux fois de suite.
  static String? _dernierAleatoire;

  /// /random-album redirige vers un album (le client HTTP Dart suit les
  /// redirections par defaut) : on en extrait le premier lien d'album de la
  /// page obtenue. Retente si le tirage reproduit le precedent.
  static Future<String> albumAuHasard() async {
    String? slug;

    for (var essai = 0; essai < 5; essai++) {
      final corps = await _get('$khBase/random-album');
      final doc = parser.parse(corps);

      slug = null;
      for (final a in doc.querySelectorAll('a')) {
        final m = _reSlug.firstMatch(a.attributes['href'] ?? '');
        if (m != null) {
          slug = m.group(1);
          break;
        }
      }

      if (slug != null && slug != _dernierAleatoire) break;
    }

    if (slug == null) {
      throw Exception('aucun album trouve sur /random-album');
    }
    _dernierAleatoire = slug;
    return slug;
  }

  /// Detail d'un album : infos + pistes.
  static Future<AlbumDetail> album(String slug) async {
    // URL construite directement, sans decodage ni re-encodage
    final corps = await _get(
      '$khBase/game-soundtracks/album/$slug',
      attendu: 'songlist',
    );
    final doc = parser.parse(corps);

    final titre = doc.querySelector('h2')?.text.trim() ?? slug;

    // Pochette : bloc "albumImage" du site, sinon premiere image de l'hebergeur
    String? pochette;
    final bloc = doc.querySelector('.albumImage a');
    final href = bloc?.attributes['href'];
    if (href != null && href.startsWith('http')) {
      pochette = assainir(href);
    } else {
      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['src'] ?? '';
        if (src.contains('vgmtreasurechest') || src.contains('vgmsite')) {
          pochette = assainir(src);
          break;
        }
      }
    }

    // Infos "Platforms: ... Album type: ... Year: ..."
    final texte = doc
        .querySelectorAll('p')
        .map((p) => p.text.replaceAll(RegExp(r'\s+'), ' '))
        .join(' ');

    String valeur(String cle) {
      // Capture bornee a 300 caracteres : si le label suivant attendu n'est
      // pas trouve dans la page (ordre inhabituel, page atypique), la seule
      // limite de secours etait la fin de la page entiere — la capture
      // avalait alors tout le reste (commentaires, autres albums...), ce qui
      // cassait l'affichage (bandeau de depassement) et figeait l'interface
      // le temps que la regex mache plusieurs Ko de texte.
      final re = RegExp(
        '$cle\\s*:\\s*(.{0,300}?)\\s*(?=(?:Platforms|Album type|Year|Developed by|'
        'Published by|Catalog Number|Number of Files|Total Filesize|Date Added|'
        'Uploaded by)\\s*:|\$)',
        dotAll: true,
      );
      return re.firstMatch(texte)?.group(1)?.trim() ?? '';
    }

    final plateformes = valeur('Platforms');
    final type = valeur('Album type');
    final annee = RegExp(r'(19|20)\d{2}').firstMatch(valeur('Year'))?.group(0) ?? '';

    // Description : meme bloc d'infos que la page web (Platforms/Year/
    // Developed by/Published by/Number of Files/Total Filesize/Date Added/
    // Uploaded by), mis en forme pour affichage sous la liste des pistes.
    final champsDescription = [
      ('Plateformes', plateformes),
      ('Année', valeur('Year')),
      ('Type', type),
      ('Développé par', valeur('Developed by')),
      ('Publié par', valeur('Published by')),
      ('Nombre de fichiers', valeur('Number of Files')),
      ('Taille totale', valeur('Total Filesize')),
      ('Ajouté le', valeur('Date Added')),
      ('Mis en ligne par', valeur('Uploaded by')),
    ];
    final description = [
      for (final (libelle, valeurChamp) in champsDescription)
        if (valeurChamp.isNotEmpty) '$libelle : $valeurChamp',
    ].join('\n');

    // Similaires : section "People who viewed this also viewed"
    final similaires = <Album>[];
    for (final h2 in doc.querySelectorAll('h2')) {
      if (!h2.text.toLowerCase().contains('people who viewed')) continue;
      var suivant = h2.nextElementSibling;
      while (suivant != null && suivant.localName != 'table') {
        suivant = suivant.nextElementSibling;
      }
      if (suivant == null) break;

      for (final td in suivant.querySelectorAll('td.albumIconLarge')) {
        final a = td.querySelector('a');
        final hrefSim = a?.attributes['href'] ?? '';
        final mSlug = _reSlug.firstMatch(hrefSim);
        if (mSlug == null) continue;

        final img = td.querySelector('img')?.attributes['src'];
        var texte =
            (td.querySelector('p')?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
        final mAnnee = RegExp(r'\((\d{4})\)\s*$').firstMatch(texte);
        final anneeSim = mAnnee?.group(1) ?? '';
        if (mAnnee != null) texte = texte.substring(0, mAnnee.start).trim();

        similaires.add(Album(
          slug: mSlug.group(1)!,
          titre: texte,
          pochette: img != null ? assainir(img) : null,
          annee: anneeSim,
        ));
      }
      break;
    }

    // Pistes : tableau #songlist
    final pistes = <Piste>[];
    final vus = <String>{};
    final table = doc.querySelector('#songlist');

    if (table != null) {
      for (final tr in table.querySelectorAll('tr')) {
        if (tr.id == 'songlist_header' || tr.id == 'songlist_footer') continue;

        String chemin = '';
        String nom = '';

        for (final a in tr.querySelectorAll('a')) {
          final h = a.attributes['href'] ?? '';
          if (!_reAudio.hasMatch(h)) continue;
          if (chemin.isEmpty) chemin = h; // premier lien : le fichier
          final t = a.text.trim();
          // La colonne de taille pointe vers le meme fichier : on l'ecarte,
          // sans quoi le titre devient "1.62 MB".
          if (t.isEmpty || _reTaille.hasMatch(t) || _estIcone(t)) continue;
          if (nom.isEmpty || t.length > nom.length) nom = t;
        }

        if (chemin.isEmpty || !vus.add(chemin)) continue;
        if (nom.isEmpty) nom = Uri.decodeFull(chemin.split('/').last);

        String duree = '';
        for (final td in tr.children.where((e) => e.localName == 'td')) {
          final t = td.text.trim();
          if (_reDuree.hasMatch(t)) {
            duree = t;
            break;
          }
        }

        pistes.add(Piste(nom: nom, chemin: chemin, duree: duree));
      }
    }

    return AlbumDetail(
      slug: slug,
      titre: titre,
      pochette: pochette,
      infos: [plateformes, type].where((s) => s.isNotEmpty).join(' · '),
      annee: annee,
      pistes: pistes,
      description: description,
      similaires: similaires,
    );
  }

  /// URL reelle du fichier audio d'une piste.
  /// Chaque piste a son propre repertoire : aucune ne se deduit d'une autre.
  static Future<String?> urlPiste(String chemin) async {
    final complet = chemin.startsWith('http') ? chemin : '$khBase$chemin';

    String corps;
    try {
      corps = await _get(complet, attendu: 'vgmtreasurechest');
    } catch (e) {
      // Certains liens de la page sont sur-encodes (%2520) : on retente
      // avec un chemin normalise avant d'abandonner.
      final normalise = normaliserChemin(chemin);
      if (normalise == chemin) rethrow;
      corps = await _get(
        chemin.startsWith('http') ? normalise : '$khBase$normalise',
        attendu: 'vgmtreasurechest',
      );
    }
    final doc = parser.parse(corps);

    // 1) Lecteur de la page
    final src = doc.querySelector('audio[src]')?.attributes['src'];
    if (src != null && src.startsWith('http')) return assainir(src);

    // 2) Lien de telechargement direct dans le contenu de la page
    final zone = doc.querySelector('#pageContent') ?? doc.body;
    for (final a in zone?.querySelectorAll('a') ?? []) {
      final h = a.attributes['href'] ?? '';
      if (!h.startsWith('http')) continue;
      if (h.contains('downloads.khinsider.com')) continue;
      if (_reAudio.hasMatch(cheminSur(h))) return assainir(h);
    }

    // Page recuperee mais sans lien audio : la structure a change,
    // ou la page renvoyee n'est pas celle attendue.
    throw Exception('lien audio absent (page de ${corps.length} octets)');
  }
}
