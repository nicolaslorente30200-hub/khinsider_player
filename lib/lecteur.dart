import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'khinsider.dart';

/// Resultat de l'initialisation du service audio d'arriere-plan.
/// Affiche par la commande "etat" du diagnostic : si l'initialisation echoue,
/// il n'y a ni notification ni lecture hors application.
String etatServiceAudio = 'non tente';

/// Lecteur unique de l'application, et gestionnaire de la file de lecture.
///
/// just_audio_background ne prend en charge **qu'un seul** AudioPlayer, celui
/// qui est rattache au service audio d'Android. En creer un par page d'album
/// donne un lecteur detache du service : pas de notification, et lecture
/// interrompue des que le systeme reprend la main.
///
/// La resolution des pistes de l'album vit ici, et non dans PageAlbum : si
/// elle vivait dans le widget, quitter la page (bouton retour) l'aurait
/// interrompue avant la fin. Tout l'album est resolu avant que la lecture
/// ne demarre, et la playlist n'est plus jamais modifiee ensuite — voir
/// _remplirBoucle pour le pourquoi.
///
/// L'instance est creee a la premiere utilisation, donc necessairement apres
/// JustAudioBackground.init() appele dans main().
class Lecteur {
  Lecteur._();

  static final Lecteur instance = Lecteur._();

  final AudioPlayer player = AudioPlayer();

  /// Dernier message technique (erreur ou etape), affiche dans le panneau
  /// de diagnostic de la page album.
  final ValueNotifier<String> journal = ValueNotifier<String>('');

  void noter(String message) {
    debugPrint('[lecteur] $message');
    journal.value = message;
  }

  // --------------------------------------------------------- File de lecture

  ConcatenatingAudioSource? _file;
  AlbumDetail? _album;
  bool _preparationEnCours = false;

  StreamSubscription<PlaybackEvent>? _suiviErreurs;

  /// Slug de l'album actuellement charge (null si aucune lecture demarree).
  final ValueNotifier<String?> slugActif = ValueNotifier<String?>(null);

  /// Pistes effectivement ajoutees a la file, dans l'ordre de lecture.
  final ValueNotifier<List<Piste>> pistesEnFile = ValueNotifier<List<Piste>>([]);

  final ValueNotifier<int> echecs = ValueNotifier<int>(0);
  final ValueNotifier<bool> preparation = ValueNotifier<bool>(false);

  AlbumDetail? get albumActif => _album;

  /// Demarre la lecture d'un album. Si c'est deja celui en cours, ne fait
  /// rien : rouvrir la page album ne doit pas repartir de la piste 1.
  void chargerAlbum(AlbumDetail album) {
    if (slugActif.value == album.slug) return;

    _suiviErreurs?.cancel();
    _suiviErreurs = null;

    _file = null;
    _album = album;
    pistesEnFile.value = [];
    echecs.value = 0;
    slugActif.value = album.slug;

    unawaited(_remplir());
  }

  AudioSource _source(Piste p, AlbumDetail album) {
    return AudioSource.uri(
      uriSure(p.url)!,
      tag: MediaItem(
        id: p.url!,
        title: p.nom,
        album: album.titre,
        artist: album.annee.isNotEmpty
            ? '${album.titre} · ${album.annee}'
            : album.titre,
        artUri: uriSure(album.pochette),
      ),
    );
  }

  /// Point d'entree : verrou de re-entrance + delegation a [_remplirBoucle].
  Future<void> _remplir() async {
    final album = _album;
    if (album == null || _preparationEnCours) return;
    _preparationEnCours = true;
    preparation.value = true;

    try {
      // Limite de temps globale, quelle que soit l'etape en cause (reseau,
      // stop/setAudioSource/play...) : sans elle, un blocage indefini d'un
      // de ces appels laissait _preparationEnCours bloque a "true" pour
      // toujours, empechant tout changement d'album suivant de meme
      // demarrer sa resolution (bloque a 0 piste). Avec la limite, on
      // abandonne au bout de 8 s et le verrou se relache normalement.
      await _remplirBoucle(album).timeout(const Duration(seconds: 8));
    } catch (e) {
      // Le verrou _preparationEnCours ne se relachait qu'apres la boucle :
      // une exception non rattrapee ici la laissait bloquee a "true" pour
      // toujours, et plus aucune piste ne se chargeait tant que rien
      // d'autre (le changement d'index a la fin de la piste en cours,
      // via _brancherSuivi) ne rappelait _remplir(). D'ou le symptome :
      // ca "debloque" au passage a la piste suivante, quelle que soit la
      // duree de la piste — ce n'etait jamais une question de delai
      // reseau, juste ce verrou jamais relache.
      noter('erreur remplissage : $e');
    }

    _preparationEnCours = false;
    preparation.value = false;

    // Si l'album a change pendant qu'on etait bloque sur une requete (par
    // exemple Kh.urlPiste en cours d'attente), le declenchement fait par
    // chargerAlbum() pour le nouvel album est arrive pendant que
    // _preparationEnCours valait encore true : le verrou l'a ignore, et rien
    // d'autre ne relance jamais le remplissage. Sans cette relance, la file
    // du nouvel album reste bloquee a 0 piste indefiniment — c'est le
    // blocage observe en changeant d'album pendant un chargement en cours.
    if (!identical(album, _album) && _album != null) {
      unawaited(_remplir());
    }
  }

  /// Resout l'URL d'une piste et construit son AudioSource. Renvoie null en
  /// cas d'echec (deja journalise). N'importe jamais au lecteur.
  Future<AudioSource?> _resoudre(Piste p, AlbumDetail album) async {
    final debut = DateTime.now();
    String? cause;
    try {
      p.url ??= await Kh.urlPiste(p.chemin);
    } catch (e) {
      p.url = null;
      cause = '$e';
    }
    final dureeMs = DateTime.now().difference(debut).inMilliseconds;

    if (p.url == null || uriSure(p.url) == null) {
      noter('${p.nom} : ${cause ?? "lien vide"}');
      echecs.value++;
      return null;
    }
    noter('${p.nom} resolue en $dureeMs ms');
    return _source(p, album);
  }

  /// Resout TOUT l'album avant de demarrer la lecture.
  ///
  /// Avant : seules quelques pistes d'avance etaient resolues, le reste
  /// arrivant au fil de la lecture via ConcatenatingAudioSource.add(). Or
  /// .add() pendant que le lecteur joue deja se bloquait indefiniment (sans
  /// exception, sans lien avec la duree d'attente) jusqu'a un evenement
  /// lecteur (pause, fin de piste) — teste et confirme : le blocage se
  /// reproduisait a l'identique, juste decale, meme en ne pre-chargeant que
  /// quelques pistes avant de demarrer. La seule sequence fiable est donc
  /// de ne plus jamais toucher la playlist une fois play() lance : tout se
  /// resout avant.
  ///
  /// Resolution en parallele (4 pistes a la fois) plutot qu'une par une,
  /// pour accelerer les gros albums (100+ pistes, plusieurs minutes sinon).
  Future<void> _remplirBoucle(AlbumDetail album) async {
    final n = album.pistes.length;
    final resultats = List<AudioSource?>.filled(n, null);
    final decidee = List<bool>.filled(n, false);
    var prochain = 0;

    void publierProgres() {
      var prefixe = 0;
      while (prefixe < n && decidee[prefixe]) {
        prefixe++;
      }
      final nouvelles = [
        for (var i = 0; i < prefixe; i++)
          if (resultats[i] != null) album.pistes[i],
      ];
      if (nouvelles.length != pistesEnFile.value.length) {
        pistesEnFile.value = nouvelles;
      }
    }

    Future<void> travailleur() async {
      while (identical(album, _album)) {
        if (prochain >= n) return;
        final i = prochain++;
        final p = album.pistes[i];

        final source = await _resoudre(p, album);
        if (!identical(album, _album)) return;
        if (source == null) {
          // Le site limite le debit : on laisse retomber la pression, puis
          // on abandonne cette piste (comme avant, pas de nouvelle tentative)
          await Future.delayed(const Duration(seconds: 2));
          if (!identical(album, _album)) return;
        }
        resultats[i] = source;
        decidee[i] = true;
        publierProgres();
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }

    const parallelisme = 4;
    await Future.wait(List.generate(parallelisme, (_) => travailleur()));

    if (!identical(album, _album)) return;
    final sources = resultats.whereType<AudioSource>().toList();
    if (sources.isEmpty) return;

    // Puis, une seule fois, demarrer la lecture avec la playlist complete.
    // Elle ne sera plus jamais modifiee ensuite : c'est precisement le
    // point qui bloquait avant, quelle que soit la quantite pre-chargee.
    //
    // Meme mecanisme en changeant d'album pendant qu'un autre joue deja :
    // remplacer la source pendant que le lecteur est actif se heurte au
    // meme blocage que .add() pendant la lecture. On arrete franchement
    // l'ancienne lecture avant de charger la nouvelle playlist, plutot
    // qu'une simple pause (on change d'album, pas juste d'idee).
    if (player.processingState != ProcessingState.idle) {
      await player.stop();
      if (!identical(album, _album)) return;
    }

    _file = ConcatenatingAudioSource(children: sources);
    await player.setAudioSource(_file!);
    if (!identical(album, _album)) return;
    await player.play();
    noter('lecture demarree : ${pistesEnFile.value.first.nom}'
        ' (album complet : ${sources.length} piste(s))');
    _brancherSuiviErreurs();
  }

  /// Rattrape les erreurs de lecture (prerequis just_audio : sans
  /// gestionnaire, une erreur reseau passagere interrompt definitivement
  /// la lecture).
  void _brancherSuiviErreurs() {
    _suiviErreurs ??= player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) async {
        noter('erreur lecture : $e');
        // On tente la piste suivante plutot que de rester bloque
        if (player.hasNext) {
          await player.seekToNext();
          await player.play();
        }
      },
    );
  }
}
