import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cast direct vers Kodi via l'API JSON-RPC.
///
/// Historique de ce qui a ete teste sur ce dossier album (plugin://
/// plugin.audio.khinsider/?action=album&slug=...) — toutes les tentatives ou
/// l'app JSON-RPC pilote elle-meme une playlist (Playlist.Add, Player.Open
/// sur un dossier ou une playlist) butent sur un bug Kodi connu et documente,
/// specifique aux PLUGINS AUDIO, ou l'avancee vers la piste suivante ne
/// fonctionne pas depuis une playlist/dossier plugin:// pilotee par
/// JSON-RPC (sujet classe "Abandoned" par le developpeur de Yatse, qui
/// indique avoir "tout essaye" cote addon) :
/// https://community.yatse.tv/t/dont-use-player-open-especially-in-case-of-music-plugins/1577
///
/// Solution retenue, trouvee en inspectant directement le trafic JSON-RPC de
/// l'interface web integree de Kodi (qui, elle, joue l'album entier avec
/// toutes les metadonnees sans probleme) : l'addon a deja une action native
/// "jouer l'album" (_jouer_album dans navigation.py, menu contextuel "Lire
/// l'album"), qui construit une xbmc.PlayList en Python et demarre la
/// lecture via xbmc.Player().play() — un mecanisme Kodi natif totalement
/// distinct de la construction de playlist par JSON-RPC, jamais concerne par
/// le bug ci-dessus. On invoque cette action via Addons.ExecuteAddon plutot
/// que de reconstruire une playlist nous-memes : verifie en direct (curl)
/// avant integration, piste 1 demarre avec titre/album/pochette corrects.
class Kodi {
  Kodi._();

  static const _cleHote = 'kodi_hote';
  static const _clePort = 'kodi_port';
  static const _cleUtilisateur = 'kodi_utilisateur';
  static const _cleMotDePasse = 'kodi_mot_de_passe';

  static Future<ConfigKodi?> configuration() async {
    final prefs = await SharedPreferences.getInstance();
    final hote = prefs.getString(_cleHote);
    if (hote == null || hote.isEmpty) return null;
    return ConfigKodi(
      hote: hote,
      port: prefs.getInt(_clePort) ?? 8080,
      utilisateur: prefs.getString(_cleUtilisateur),
      motDePasse: prefs.getString(_cleMotDePasse),
    );
  }

  static Future<void> enregistrer(ConfigKodi config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cleHote, config.hote);
    await prefs.setInt(_clePort, config.port);
    if (config.utilisateur != null && config.utilisateur!.isNotEmpty) {
      await prefs.setString(_cleUtilisateur, config.utilisateur!);
    } else {
      await prefs.remove(_cleUtilisateur);
    }
    if (config.motDePasse != null && config.motDePasse!.isNotEmpty) {
      await prefs.setString(_cleMotDePasse, config.motDePasse!);
    } else {
      await prefs.remove(_cleMotDePasse);
    }
  }

  /// Appel JSON-RPC generique. Leve une exception avec un message distinct
  /// pour chaque cause d'echec (injoignable / HTTP / auth / erreur Kodi),
  /// pour pouvoir diagnostiquer depuis le message affiche dans l'app.
  static Future<dynamic> _rpc(
    ConfigKodi config,
    String methode,
    Map<String, dynamic> params,
  ) async {
    final uri = Uri.http('${config.hote}:${config.port}', '/jsonrpc');

    final entetes = {'Content-Type': 'application/json'};
    if (config.utilisateur != null && config.utilisateur!.isNotEmpty) {
      final jeton =
          base64Encode(utf8.encode('${config.utilisateur}:${config.motDePasse ?? ''}'));
      entetes['Authorization'] = 'Basic $jeton';
    }

    final corps = jsonEncode({
      'jsonrpc': '2.0',
      'method': methode,
      'params': params,
      'id': 1,
    });

    final http.Response rep;
    try {
      rep = await http.post(uri, headers: entetes, body: corps)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      throw Exception('Kodi injoignable ($e)');
    }

    if (rep.statusCode == 401) {
      throw Exception('Authentification Kodi refusee');
    }
    if (rep.statusCode != 200) {
      throw Exception('Kodi a repondu HTTP ${rep.statusCode}');
    }

    final donnees = jsonDecode(rep.body);
    debugPrint('[kodi] $methode -> ${rep.body}');
    if (donnees is Map && donnees['error'] != null) {
      throw Exception('Erreur Kodi ($methode) : ${donnees['error']}');
    }
    return donnees is Map ? donnees['result'] : null;
  }

  static Future<void> casterAlbum(ConfigKodi config, String slugAlbum) async {
    await _rpc(config, 'Addons.ExecuteAddon', {
      'addonid': 'plugin.audio.khinsider',
      'params': {'action': 'jouer', 'slug': slugAlbum},
    });

    // Sans ceci, Kodi reste momentanement sur l'ecran de navigation du
    // module musique le temps que l'addon s'execute, plutot que de basculer
    // directement sur l'ecran de lecture plein ecran. On force donc la
    // fenetre "visualisation" (l'ecran plein ecran audio "En cours de
    // lecture") une fois la lecture demarree.
    try {
      await _rpc(config, 'GUI.ActivateWindow', {'window': 'visualisation'});
    } catch (e) {
      debugPrint('[kodi] GUI.ActivateWindow a echoue (sans gravite) : $e');
    }
  }
}

class ConfigKodi {
  final String hote;
  final int port;
  final String? utilisateur;
  final String? motDePasse;

  const ConfigKodi({
    required this.hote,
    this.port = 8080,
    this.utilisateur,
    this.motDePasse,
  });
}
