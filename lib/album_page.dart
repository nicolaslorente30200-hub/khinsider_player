import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'khinsider.dart';
import 'kodi.dart';
import 'lecteur.dart';
import 'main.dart';

/// Canal natif (voir MainActivity.kt, injecte par tools/patch_android.py) :
/// enregistre un fichier deja sur le disque dans le dossier Telechargements
/// public via MediaStore — une simple ecriture par chemin de fichier est
/// bloquee par le stockage cloisonne depuis Android 10.
const _canalTelechargements = MethodChannel('xyz.perso.khinsider_ost/telechargements');

class PageAlbum extends StatefulWidget {
  final String slug;
  const PageAlbum({super.key, required this.slug});

  @override
  State<PageAlbum> createState() => _PageAlbumState();
}

class _PageAlbumState extends State<PageAlbum> {
  /// Lecteur unique de l'application (seul rattache au service audio).
  final AudioPlayer _lecteur = Lecteur.instance.player;

  AlbumDetail? _album;
  String? _erreur;

  /// positionStream emet tres frequemment (plusieurs fois par seconde) :
  /// sur un GPU d'entree de gamme, ces reconstructions en continu pendant
  /// la lecture saturaient le pipeline de rendu (Impeller/Vulkan), au point
  /// de mettre en attente le traitement d'un travail deja termine (la
  /// resolution de la piste suivante) — observe : la file restait bloquee
  /// tant que la lecture tournait, et repartait des qu'on mettait pause.
  /// On limite donc la frequence de rafraichissement a 1x/seconde.
  late final Stream<Duration> _positionThrottlee = _lecteur.positionStream
      .map((d) => Duration(seconds: d.inSeconds))
      .distinct();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // Pas de dispose() a ecrire : la file d'attente et son suivi vivent dans
  // Lecteur.instance (voir lecteur.dart), independamment de cette page.
  // C'est le point du bug corrige : ils survivent au bouton retour.

  Future<void> _charger() async {
    setState(() => _erreur = null);

    try {
      final AlbumDetail album;
      if (Lecteur.instance.slugActif.value == widget.slug &&
          Lecteur.instance.albumActif != null) {
        // Meme album deja en cours de lecture (ex. retour puis reouverture
        // de la page) : on reprend l'etat existant, pas de nouvelle requete
        // ni de redemarrage de la file depuis la piste 1.
        album = Lecteur.instance.albumActif!;
      } else {
        album = await Kh.album(widget.slug);
        Lecteur.instance.chargerAlbum(album);
      }
      if (!mounted) return;
      setState(() => _album = album);

      if (album.pistes.isEmpty) {
        setState(() => _erreur = 'Aucune piste détectée sur cet album.');
      }
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  /// Envoie l'album a Kodi via l'action native de l'addon (voir kodi.dart) :
  /// invoquee via Addons.ExecuteAddon, avec toutes les metadonnees.
  Future<void> _casterKodi(AlbumDetail album) async {
    var config = await Kodi.configuration();
    config ??= await _configurerKodi();
    if (config == null) return;

    try {
      await Kodi.casterAlbum(config, album.slug);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Envoyé à Kodi : ${album.titre}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec du cast Kodi : $e')),
        );
      }
    }
  }

  /// Telecharge toutes les pistes et les enregistre en une archive .zip
  /// dans le dossier Telechargements public — equivalent mobile de
  /// download.php sur le site web (meme principe : recuperer chaque piste,
  /// les compresser, servir une seule archive).
  bool _telechargementEnCours = false;

  Future<void> _telechargerAlbum(AlbumDetail album) async {
    if (_telechargementEnCours) return;
    setState(() => _telechargementEnCours = true);

    File? fichierTmp;
    try {
      final zip = Archive();
      var recuperees = 0;

      for (var i = 0; i < album.pistes.length; i++) {
        final piste = album.pistes[i];
        piste.url ??= await Kh.urlPiste(piste.chemin);
        final url = piste.url;
        if (url == null) continue;

        final reponse = await http.get(Uri.parse(url));
        if (reponse.statusCode != 200) continue;

        final numero = (i + 1).toString().padLeft(2, '0');
        final extension = url.split('.').last.split('?').first;
        final nomPiste = '$numero - ${piste.nom}.$extension'
            .replaceAll(RegExp(r'[\/\\:*?"<>|]'), '_');

        zip.addFile(ArchiveFile(nomPiste, reponse.bodyBytes.length, reponse.bodyBytes));
        recuperees++;
      }

      if (recuperees == 0) {
        throw Exception('Aucune piste n\'a pu être récupérée.');
      }

      final octetsZip = ZipEncoder().encode(zip);
      if (octetsZip == null) {
        throw Exception('Échec de la compression de l\'archive.');
      }
      final nomZip = '${album.titre}.zip'.replaceAll(RegExp(r'[\/\\:*?"<>|]'), '_');

      final dossierTmp = await getTemporaryDirectory();
      fichierTmp = File('${dossierTmp.path}/$nomZip');
      await fichierTmp.writeAsBytes(octetsZip);

      final uri = await _canalTelechargements.invokeMethod<String>(
        'enregistrerDansTelechargements',
        {'chemin': fichierTmp.path, 'nom': nomZip},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(uri != null
              ? 'Archive téléchargée : $nomZip ($recuperees pistes)'
              : 'Échec de l\'enregistrement de l\'archive'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Échec du téléchargement : $e')));
      }
    } finally {
      if (fichierTmp != null) {
        try {
          await fichierTmp.delete();
        } catch (_) {
          // Fichier temporaire deja absent ou verrouille : sans consequence.
        }
      }
      if (mounted) setState(() => _telechargementEnCours = false);
    }
  }

  Future<ConfigKodi?> _configurerKodi() async {
    final existant = await Kodi.configuration();
    final hoteCtrl = TextEditingController(text: existant?.hote ?? '');
    final portCtrl = TextEditingController(text: (existant?.port ?? 8080).toString());
    final utilisateurCtrl = TextEditingController(text: existant?.utilisateur ?? '');
    final motDePasseCtrl = TextEditingController(text: existant?.motDePasse ?? '');

    if (!mounted) return null;
    final resultat = await showDialog<ConfigKodi>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        backgroundColor: kSurface,
        title: Text('Configuration Kodi', style: TextStyle(color: kText)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hoteCtrl,
                style: TextStyle(color: kText),
                decoration: const InputDecoration(
                  labelText: 'Adresse IP de la box',
                  helperText: 'Adresse IP obligatoire : Android ne résout pas '
                      'les noms .local (mDNS), contrairement à iOS/macOS.',
                  helperMaxLines: 2,
                ),
              ),
              TextField(
                controller: portCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Port (8080 par défaut)'),
              ),
              TextField(
                controller: utilisateurCtrl,
                style: TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Utilisateur (optionnel)'),
              ),
              TextField(
                controller: motDePasseCtrl,
                obscureText: true,
                style: TextStyle(color: kText),
                decoration: const InputDecoration(labelText: 'Mot de passe (optionnel)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final hote = hoteCtrl.text.trim();
              if (hote.isEmpty) return;
              Navigator.of(contexteDialogue).pop(ConfigKodi(
                hote: hote,
                port: int.tryParse(portCtrl.text.trim()) ?? 8080,
                utilisateur: utilisateurCtrl.text.trim(),
                motDePasse: motDePasseCtrl.text,
              ));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (resultat != null) {
      await Kodi.enregistrer(resultat);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration Kodi enregistrée.')),
        );
      }
    }
    return resultat;
  }

  @override
  Widget build(BuildContext context) {
    final album = _album;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (album != null)
            IconButton(
              tooltip: 'Télécharger l\'album (archive .zip)',
              icon: _telechargementEnCours
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kAmber),
                    )
                  : Icon(Icons.download, color: kAmber),
              onPressed: _telechargementEnCours ? null : () => _telechargerAlbum(album),
            ),
          if (album != null)
            IconButton(
              tooltip: 'Caster sur Kodi (appui long : configurer l\'adresse)',
              icon: Icon(Icons.cast, color: kAmber),
              onPressed: () => _casterKodi(album),
              onLongPress: () => _configurerKodi(),
            ),
        ],
      ),
      body: album == null
          ? (_erreur != null
              ? _messageErreur()
              : Center(child: CircularProgressIndicator(color: kAmber)))
          : (_erreur != null
              ? Column(
                  children: [_entete(album), Expanded(child: _messageErreur())],
                )
              // Tout dans un seul CustomScrollView (en-tete inclus) : en
              // format paysage, l'en-tete + la barre du bas laissaient trop
              // peu de hauteur a une liste figee par Expanded, et rien
              // n'etait scrollable pour rattraper le manque de place.
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _entete(album)),
                    SliverToBoxAdapter(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: Lecteur.instance.preparation,
                        builder: (context, preparation, _) => preparation
                            ? _progression(album)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    _listePistes(album),
                    SliverToBoxAdapter(child: _description(album)),
                    SliverToBoxAdapter(child: _similaires(album)),
                    // Marge basse dynamique : sans elle, les suggestions se
                    // retrouvent en partie cachees sous la barre de
                    // navigation systeme quand la barre de lecture n'est pas
                    // affichee (aucune piste en file, donc pas de
                    // bottomNavigationBar pour reserver cette zone).
                    SliverToBoxAdapter(
                      child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
                    ),
                  ],
                )),
      bottomNavigationBar: ValueListenableBuilder<List<Piste>>(
        valueListenable: Lecteur.instance.pistesEnFile,
        builder: (context, enFile, _) =>
            enFile.isNotEmpty ? _barreLecteur() : const SizedBox.shrink(),
      ),
    );
  }

  Widget _entete(AlbumDetail album) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pochette(url: album.pochette, taille: 110, titre: album.titre),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.titre,
                    style: TextStyle(
                        color: kText, fontSize: 17, fontWeight: FontWeight.bold)),
                if (album.infos.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(album.infos,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: kMuted, fontSize: 13)),
                ],
                if (album.annee.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(album.annee,
                      style: TextStyle(
                          color: kAmberDim,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 6),
                ValueListenableBuilder<int>(
                  valueListenable: Lecteur.instance.echecs,
                  builder: (context, echecs, _) => Text(
                    '${album.pistes.length} pistes'
                    '${echecs > 0 ? " · $echecs indisponible(s)" : ""}',
                    style: TextStyle(color: kMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progression(AlbumDetail album) {
    return ValueListenableBuilder<List<Piste>>(
      valueListenable: Lecteur.instance.pistesEnFile,
      builder: (context, enFile, _) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border.all(color: kLine),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Pas de CircularProgressIndicator ici : c'est une animation en
            // boucle (AnimationController.repeat()) qui, combinee a
            // Impeller/Vulkan sur certains GPU d'entree de gamme (bug connu,
            // cf. flutter/flutter#184655), sature le pipeline de rendu au
            // point de mettre en pause tout le reste — y compris le
            // traitement du resultat deja arrive de la piste suivante. Une
            // icone fixe evite de declencher ce bug.
            Icon(Icons.cloud_download_outlined, size: 18, color: kAmber),
            const SizedBox(width: 12),
            Text('Piste ${enFile.length} / ${album.pistes.length}',
                style: TextStyle(color: kMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _listePistes(AlbumDetail album) {
    return ValueListenableBuilder<List<Piste>>(
      valueListenable: Lecteur.instance.pistesEnFile,
      builder: (context, enFile, _) => StreamBuilder<int?>(
        stream: _lecteur.currentIndexStream,
        builder: (context, snap) {
          final courant = snap.data;
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final p = album.pistes[i];
                final position = enFile.indexOf(p); // -1 si pas encore prete
                final prete = position >= 0;
                final actif = prete && courant == position;

                return Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: kLine, width: 1)),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Text(
                      (i + 1).toString().padLeft(2, '0'),
                      style: TextStyle(
                          color: actif ? kAmber : kMuted, fontSize: 13),
                    ),
                    title: Text(
                      p.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: actif ? kAmber : (prete ? kText : kMuted),
                        fontWeight: actif ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Text(
                      prete ? p.duree : '…',
                      style: TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                    onTap: prete
                        ? () {
                            _lecteur.seek(Duration.zero, index: position);
                            _lecteur.play();
                          }
                        : null,
                  ),
                );
              },
              childCount: album.pistes.length,
            ),
          );
        },
      ),
    );
  }

  /// Bloc "Platforms/Year/Developed by/..." de la page album du site,
  /// affiche sous la liste des pistes.
  Widget _description(AlbumDetail album) {
    if (album.description.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        border: Border.all(color: kLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Description',
              style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(album.description,
              style: TextStyle(color: kMuted, fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  /// Section "People who viewed this also viewed" de la page album du site.
  Widget _similaires(AlbumDetail album) {
    if (album.similaires.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suggestions',
              style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: album.similaires.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final a = album.similaires[i];
                return SizedBox(
                  width: 110,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PageAlbum(slug: a.slug)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pochette(url: a.pochette, taille: 110, titre: a.titre),
                        const SizedBox(height: 6),
                        Text(a.titre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: kText, fontSize: 12.5)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreLecteur() {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: kLine)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<SequenceState?>(
              stream: _lecteur.sequenceStateStream,
              builder: (context, snap) {
                final item = snap.data?.currentSource?.tag as MediaItem?;
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        item?.title ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: kAmber, fontSize: 14),
                      ),
                    ),
                    StreamBuilder<Duration>(
                      stream: _positionThrottlee,
                      builder: (context, s) {
                        final d = s.data ?? Duration.zero;
                        return Text(
                          '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(color: kMuted, fontSize: 13),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            StreamBuilder<Duration>(
              stream: _positionThrottlee,
              builder: (context, snapPos) {
                final duree = _lecteur.duration ?? Duration.zero;
                final pos = snapPos.data ?? Duration.zero;
                final max = duree.inMilliseconds.toDouble();
                final val =
                    pos.inMilliseconds.clamp(0, duree.inMilliseconds).toDouble();
                return SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: kAmber,
                    inactiveTrackColor: kLine,
                    thumbColor: kAmber,
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    min: 0,
                    max: max > 0 ? max : 1,
                    value: max > 0 ? val : 0,
                    onChanged: max > 0
                        ? (v) => _lecteur.seek(Duration(milliseconds: v.round()))
                        : null,
                  ),
                );
              },
            ),
            // Espace avant les boutons : sans lui, le curseur de la barre de
            // progression juste au-dessus est trop proche du bouton lecture/
            // pause, au point de le declencher par erreur en manipulant la
            // barre. Le bouton lecture/pause est aussi reduit (mini) pour la
            // meme raison, et rapproche visuellement des boutons precedent/
            // suivant plutot que de s'en demarquer par sa taille.
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.skip_previous, color: kText),
                  onPressed:
                      _lecteur.hasPrevious ? _lecteur.seekToPrevious : null,
                ),
                const SizedBox(width: 12),
                StreamBuilder<PlayerState>(
                  stream: _lecteur.playerStateStream,
                  builder: (context, snap) {
                    final enLecture = snap.data?.playing ?? false;
                    return FloatingActionButton(
                      mini: true,
                      backgroundColor: kAmber,
                      foregroundColor: const Color(0xFF1A1206),
                      elevation: 0,
                      onPressed: enLecture ? _lecteur.pause : _lecteur.play,
                      child: Icon(enLecture ? Icons.pause : Icons.play_arrow),
                    );
                  },
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: Icon(Icons.skip_next, color: kText),
                  onPressed: _lecteur.hasNext ? _lecteur.seekToNext : null,
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Stop',
                  icon: Icon(Icons.stop, color: kMuted),
                  onPressed: Lecteur.instance.arreter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: kMuted, size: 36),
            const SizedBox(height: 12),
            Text(_erreur ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _charger,
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
