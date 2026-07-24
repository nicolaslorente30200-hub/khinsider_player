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
    patch_min_sdk()

    if erreurs:
        print('\n=== ECHEC DE LA CONFIGURATION ANDROID ===')
        for e in erreurs:
            print(' -', e)
        sys.exit(1)

    print('Configuration Android validee : service audio en arriere-plan actif.')
