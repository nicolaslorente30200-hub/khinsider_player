# -*- coding: utf-8 -*-
"""Service Kodi : lit les albums envoyes par l'app Android KHINSIDER·ost.

L'app appelle JSON-RPC JSONRPC.NotifyAll (message "khinsider_cast") avec
l'album et ses pistes deja resolues (liens mp3 directs). Ce service ne
contacte jamais khinsider.com : il se contente de construire la playlist
avec toutes les metadonnees (titre, album, annee, pochette...), ce qu'un
simple Playlist.Add de liens bruts ne permet pas.

Charge attendue (JSON) :
{
  "album":  {"titre": str, "annee": str, "pochette": str, "artiste": str,
             "genre": str},
  "pistes": [{"titre": str, "url": str, "duree": int (secondes, optionnel)}]
}
"""
import json

import xbmc
import xbmcgui

ID = 'service.khinsider.cast'
MESSAGE = 'khinsider_cast'


def log(texte, niveau=xbmc.LOGINFO):
    xbmc.log('[%s] %s' % (ID, texte), niveau)


def poser_infos(item, titre, album, annee, numero, duree, artiste, genre):
    """Kodi 20+ : InfoTagMusic ; Kodi 19 : setInfo (seule API disponible)."""
    try:
        tag = item.getMusicInfoTag()
        tag.setTitle(titre)
        tag.setAlbum(album)
        tag.setTrack(numero)
        if annee:
            tag.setYear(annee)
        if duree:
            tag.setDuration(duree)
        if artiste:
            tag.setArtist(artiste)
            tag.setAlbumArtist(artiste)
        if genre:
            tag.setGenres([genre])
    except (AttributeError, TypeError):
        infos = {'title': titre, 'album': album, 'tracknumber': numero}
        if annee:
            infos['year'] = annee
        if duree:
            infos['duration'] = duree
        if artiste:
            infos['artist'] = artiste
            infos['albumartist'] = artiste
        if genre:
            infos['genre'] = genre
        item.setInfo('music', infos)


def lancer(charge):
    album = charge.get('album') or {}
    pistes = charge.get('pistes') or []
    if not pistes:
        raise ValueError('aucune piste recue')

    titre_album = album.get('titre', '')
    try:
        annee = int(album.get('annee') or 0)
    except ValueError:
        annee = 0
    pochette = album.get('pochette') or ''
    artiste = album.get('artiste') or ''
    genre = album.get('genre') or ''

    liste = xbmc.PlayList(xbmc.PLAYLIST_MUSIC)
    liste.clear()

    for numero, piste in enumerate(pistes, 1):
        item = xbmcgui.ListItem(label=piste.get('titre', ''), path=piste['url'])
        poser_infos(item, piste.get('titre', ''), titre_album, annee, numero,
                    int(piste.get('duree') or 0), artiste, genre)
        if pochette:
            item.setArt({'thumb': pochette, 'icon': pochette, 'fanart': pochette})
        liste.add(piste['url'], item)

    log('lecture de "%s" (%d pistes)' % (titre_album, len(pistes)))
    xbmc.Player().play(liste, startpos=0)


class Moniteur(xbmc.Monitor):
    def onNotification(self, sender, method, data):
        if not method.endswith(MESSAGE):
            return
        try:
            charge = json.loads(data)
            # Selon la version de Kodi, la charge arrive seule ou dans une liste.
            if isinstance(charge, list) and charge:
                charge = charge[0]
            lancer(charge)
        except Exception as e:  # noqa: BLE001 - on veut tout journaliser
            log('echec : %s' % e, xbmc.LOGERROR)
            xbmcgui.Dialog().notification(
                'KHINSIDER·ost', 'Échec du cast : %s' % e,
                xbmcgui.NOTIFICATION_ERROR)


if __name__ == '__main__':
    moniteur = Moniteur()
    log('service demarre')
    while not moniteur.abortRequested():
        if moniteur.waitForAbort(10):
            break
    log('service arrete')
