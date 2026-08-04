#!/usr/bin/env python3
"""Configure Android pour la lecture audio en arriere-plan (just_audio_background).

Sans le service declare et la permission FOREGROUND_SERVICE_MEDIA_PLAYBACK,
Android 14+ ne demarre pas correctement le service au premier plan : la lecture
s'arrete au bout de quelques minutes en arriere-plan et aucune notification
media n'apparait.

Le script echoue volontairement si une modification n'a pas pu etre appliquee :
mieux vaut une compilation en erreur qu'un APK silencieusement casse.
"""
import glob
import os
import re
import sys

MANIFESTE = 'android/app/src/main/AndroidManifest.xml'

PERMISSIONS = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
"""

SERVICE = """
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
"""

erreurs = []


def patch_manifeste():
    if not os.path.isfile(MANIFESTE):
        erreurs.append(f'Manifeste introuvable : {MANIFESTE}')
        return

    src = open(MANIFESTE, encoding='utf-8').read()

    # Espace de noms "tools" (requis par tools:ignore)
    if 'xmlns:tools' not in src:
        src, n = re.subn(
            r'(<manifest\b[^>]*?)>',
            r'\1\n    xmlns:tools="http://schemas.android.com/tools">',
            src, count=1, flags=re.S)
        if n == 0:
            erreurs.append('Impossible d\'ajouter xmlns:tools')

    # Permissions, avant <application ...>
    if 'FOREGROUND_SERVICE_MEDIA_PLAYBACK' not in src:
        src, n = re.subn(r'([ \t]*)<application\b', PERMISSIONS + r'\1<application',
                         src, count=1)
        if n == 0:
            erreurs.append('Impossible d\'inserer les permissions')

    # usesCleartextTraffic : le proxy interne de just_audio tourne sur un
    # serveur HTTP local ; sans cet attribut il est bloque par Android.
    if 'usesCleartextTraffic' not in src:
        src, n = re.subn(r'(<application\b)', r'\1\n        android:usesCleartextTraffic="true"',
                         src, count=1)
        if n == 0:
            erreurs.append('Impossible d\'ajouter usesCleartextTraffic')

    # Service + recepteur, avant </application>
    if 'com.ryanheise.audioservice.AudioService' not in src:
        src, n = re.subn(r'([ \t]*)</application>', SERVICE + r'\1</application>',
                         src, count=1)
        if n == 0:
            erreurs.append('Impossible d\'inserer le service audio')

    open(MANIFESTE, 'w', encoding='utf-8').write(src)

    # Verification finale
    final = open(MANIFESTE, encoding='utf-8').read()
    for attendu, libelle in [
        ('FOREGROUND_SERVICE_MEDIA_PLAYBACK', 'permission media playback'),
        ('POST_NOTIFICATIONS', 'permission notifications'),
        ('READ_EXTERNAL_STORAGE', 'permission lecture stockage (telechargement zip)'),
        ('WRITE_EXTERNAL_STORAGE', 'permission ecriture stockage (telechargement zip)'),
        ('com.ryanheise.audioservice.AudioService', 'service audio'),
        ('com.ryanheise.audioservice.MediaButtonReceiver', 'recepteur boutons media'),
        ('xmlns:tools', 'espace de noms tools'),
        ('usesCleartextTraffic', 'trafic local autorise'),
    ]:
        if attendu not in final:
            erreurs.append(f'Manifeste : {libelle} absent apres patch')
    print('AndroidManifest.xml traite.')


def patch_activite():
    """MainActivity doit heriter d'AudioServiceActivity."""
    fichiers = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)
    fichiers += glob.glob('android/app/src/main/java/**/MainActivity.java', recursive=True)

    if not fichiers:
        erreurs.append('MainActivity introuvable')
        return

    for f in fichiers:
        src = open(f, encoding='utf-8').read()
        if 'AudioServiceActivity' not in src:
            src = src.replace(
                'import io.flutter.embedding.android.FlutterActivity',
                'import com.ryanheise.audioservice.AudioServiceActivity')
            src = re.sub(r'\bFlutterActivity\b', 'AudioServiceActivity', src)
            open(f, 'w', encoding='utf-8').write(src)

        final = open(f, encoding='utf-8').read()
        if 'AudioServiceActivity' not in final:
            erreurs.append(f'{f} : heritage AudioServiceActivity absent')
        else:
            print(f'{f} traite.')


CANAL_TELECHARGEMENTS = 'xyz.perso.khinsider_ost/telechargements'

IMPORTS_TELECHARGEMENT = """import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
"""

CORPS_ACTIVITE = '''class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Enregistre l'archive .zip d'un album dans le dossier
        // Telechargements public : le stockage cloisonne depuis Android 10
        // interdit l'ecriture directe par chemin de fichier dans ce dossier
        // partage, MediaStore est la seule API fiable sur toutes versions.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "''' + CANAL_TELECHARGEMENTS + '''")
            .setMethodCallHandler { call, result ->
                if (call.method == "enregistrerDansTelechargements") {
                    val chemin = call.argument<String>("chemin")
                    val nom = call.argument<String>("nom")
                    if (chemin == null || nom == null) {
                        result.error("ARGS", "chemin/nom manquant", null)
                    } else {
                        try {
                            result.success(enregistrerDansTelechargements(chemin, nom))
                        } catch (e: Exception) {
                            result.error("ECHEC", e.message, null)
                        }
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun enregistrerDansTelechargements(chemin: String, nom: String): String {
        val source = File(chemin)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val dossier = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!dossier.exists()) dossier.mkdirs()
            val destination = File(dossier, nom)
            source.copyTo(destination, overwrite = true)
            return destination.absolutePath
        }

        val valeurs = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, nom)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/")
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, valeurs)
            ?: throw Exception("Impossible de creer l'entree MediaStore")
        contentResolver.openOutputStream(uri)?.use { sortie ->
            source.inputStream().use { entree -> entree.copyTo(sortie) }
        } ?: throw Exception("Impossible d'ouvrir le flux d'ecriture")
        return uri.toString()
    }
}
'''


def patch_telechargement():
    """Canal natif MediaStore pour enregistrer l'archive .zip d'un album
    dans le dossier Telechargements public (voir PageAlbum._telechargerAlbum
    cote Dart). Necessaire car android/ est regenere a chaque build CI :
    sans ce patch, MainActivity.kt perd ce code a chaque compilation."""
    fichiers = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)

    if not fichiers:
        erreurs.append('MainActivity.kt introuvable (canal telechargements)')
        return

    for f in fichiers:
        src = open(f, encoding='utf-8').read()
        if CANAL_TELECHARGEMENTS in src:
            print(f'{f} : canal telechargements deja present.')
            continue

        src = src.replace(
            'import com.ryanheise.audioservice.AudioServiceActivity\n',
            IMPORTS_TELECHARGEMENT)

        src, n = re.subn(r'class MainActivity\s*:\s*AudioServiceActivity\(\)\s*\n?',
                         CORPS_ACTIVITE, src, count=1)
        if n == 0:
            erreurs.append(f'{f} : corps de classe introuvable pour le canal telechargements')
            continue

        open(f, 'w', encoding='utf-8').write(src)

        final = open(f, encoding='utf-8').read()
        if CANAL_TELECHARGEMENTS not in final:
            erreurs.append(f'{f} : canal telechargements absent apres patch')
        else:
            print(f'{f} : canal telechargements ajoute.')


def patch_shrink_resources():
    """Desactive shrinkResources pour le build release.

    audio_service fournit ses icones de notification (play/pause/skip...)
    comme ressources bundlees, recherchees au runtime par nom via
    getIdentifier() plutot que par reference R.drawable statique. L'analyse
    statique du "resource shrinker" d'Android ne voit donc aucune reference
    a ces drawables et les supprime du build release comme "inutilises" :
    au premier essai de construction de la notification, l'icone recherchee
    vaut alors 0, ce qui fait planter audio_service avec
    "You must specify an icon resource id to build a CustomAction" — et donc
    aucune notification ne s'affiche jamais en release (marchait en debug,
    ou shrinkResources est desactive par defaut).
    """
    fichiers = [f for f in ('android/app/build.gradle.kts', 'android/app/build.gradle')
                if os.path.isfile(f)]
    if not fichiers:
        erreurs.append('build.gradle introuvable')
        return

    for f in fichiers:
        src = open(f, encoding='utf-8').read()
        avant = src

        if 'isShrinkResources' not in src and 'shrinkResources' not in src:
            if f.endswith('.kts'):
                src, n = re.subn(r'(release\s*\{)', r'\1\n            isShrinkResources = false',
                                 src, count=1)
            else:
                src, n = re.subn(r'(release\s*\{)', r'\1\n            shrinkResources false',
                                 src, count=1)
            if n == 0:
                erreurs.append(f'{f} : bloc release introuvable pour shrinkResources')

        if src != avant:
            open(f, 'w', encoding='utf-8').write(src)
            print(f'{f} : shrinkResources desactive.')
        else:
            print(f'{f} : shrinkResources deja configure.')

        final = open(f, encoding='utf-8').read()
        if 'isShrinkResources = false' not in final and 'shrinkResources false' not in final:
            erreurs.append(f'{f} : shrinkResources toujours actif apres patch')


def patch_compile_sdk():
    """media_store_plus / shared_preferences / sqflite exigent compileSdk >= 36."""
    fichiers = [f for f in ('android/app/build.gradle.kts', 'android/app/build.gradle')
                if os.path.isfile(f)]
    if not fichiers:
        erreurs.append('build.gradle introuvable')
        return

    for f in fichiers:
        src = open(f, encoding='utf-8').read()
        avant = src

        src = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36', src)
        src = re.sub(r'compileSdk(?:Version)?\s*=?\s*(\d+)',
                     lambda m: 'compileSdk = 36' if int(m.group(1)) < 36 else m.group(0), src)

        if src != avant:
            open(f, 'w', encoding='utf-8').write(src)
            print(f'{f} : compileSdk porte a 36.')
        else:
            print(f'{f} : compileSdk deja conforme.')

        final = open(f, encoding='utf-8').read()
        trouve = re.search(r'compileSdk\s*=\s*(\d+)', final)
        if not trouve or int(trouve.group(1)) < 36:
            erreurs.append(f'{f} : compileSdk toujours < 36')


def patch_min_sdk():
    """audio_service exige minSdk 23 ; Flutter genere parfois une valeur plus basse."""
    fichiers = [f for f in ('android/app/build.gradle.kts', 'android/app/build.gradle')
                if os.path.isfile(f)]
    if not fichiers:
        erreurs.append('build.gradle introuvable')
        return

    for f in fichiers:
        src = open(f, encoding='utf-8').read()
        avant = src

        # Formes rencontrees : minSdk = 21 / minSdkVersion 21 / flutter.minSdkVersion
        src = re.sub(r'minSdk(?:Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23', src)
        src = re.sub(r'minSdk(?:Version)?\s*=\s*(\d+)',
                     lambda m: 'minSdk = 23' if int(m.group(1)) < 23 else m.group(0), src)
        src = re.sub(r'minSdkVersion\s+(\d+)',
                     lambda m: 'minSdkVersion 23' if int(m.group(1)) < 23 else m.group(0), src)

        if src != avant:
            open(f, 'w', encoding='utf-8').write(src)
            print(f'{f} : minSdk porte a 23.')
        else:
            print(f'{f} : minSdk deja conforme.')

        final = open(f, encoding='utf-8').read()
        trouve = re.search(r'minSdk(?:Version)?\s*=?\s*(\d+)', final)
        if trouve and int(trouve.group(1)) < 23:
            erreurs.append(f'{f} : minSdk toujours < 23')


if __name__ == '__main__':
    patch_manifeste()
    patch_activite()
    patch_telechargement()
    patch_shrink_resources()
    patch_compile_sdk()
    patch_min_sdk()

    if erreurs:
        print('\n=== ECHEC DE LA CONFIGURATION ANDROID ===')
        for e in erreurs:
            print(' -', e)
        sys.exit(1)

    print('Configuration Android validee : service audio en arriere-plan actif.')
