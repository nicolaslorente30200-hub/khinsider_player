package xyz.perso.khinsider_ost

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Enregistre l'archive .zip d'un album dans le dossier
        // Telechargements public : le stockage cloisonne depuis Android 10
        // interdit l'ecriture directe par chemin de fichier dans ce dossier
        // partage, MediaStore est la seule API fiable sur toutes versions.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xyz.perso.khinsider_ost/telechargements")
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
