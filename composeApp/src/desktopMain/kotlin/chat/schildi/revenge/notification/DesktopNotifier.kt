package chat.schildi.revenge.notification

import chat.schildi.revenge.Destination
import chat.schildi.revenge.UiState
import co.touchlab.kermit.Logger
import io.element.android.libraries.matrix.api.media.MediaSource
import io.github.kdroidfilter.knotify.builder.AppConfig
import io.github.kdroidfilter.knotify.builder.ExperimentalNotificationsApi
import io.github.kdroidfilter.knotify.builder.NotificationInitializer
import io.github.kdroidfilter.knotify.builder.sendNotification
import kotlinx.coroutines.withTimeoutOrNull
import org.jetbrains.compose.resources.getString
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import shire.res.generated.resources.Res
import shire.res.generated.resources.app_title_short
import java.nio.file.Files
import kotlin.time.Duration.Companion.milliseconds

object DesktopNotifier {
    private val log = Logger.withTag("Notifier")

    suspend fun initialize() {
        NotificationInitializer.configure(
            AppConfig(
                appName = getString(Res.string.app_title_short),
                smallIcon = Res.getUri("drawable-xhdpi/ic_launcher.png")
            )
        )
    }

    private fun onNotificationActivated(id: NotificationId) {
        val room = id as? NotificationId.ForRoom
        val sessionId = id.sessionId
        if (room == null || sessionId == null) {
            // Nothing specific to open, but still bring the app back if it is hidden
            UiState.setMinimized(false)
            return
        }
        UiState.openWindow(
            Destination.Conversation(sessionId = sessionId, roomId = room.roomId),
            preferNewTask = false,
        )
    }

    @OptIn(ExperimentalNotificationsApi::class)
    suspend fun notify(
        id: NotificationId,
        title: String,
        message: String,
        largeImage: MediaSource? = null,
    ) {
        val largeIconFile = largeImage?.let {
            val client = id.sessionId?.let { UiState.currentClientFor(it) } ?: return@let null
            withTimeoutOrNull(3000.milliseconds) {
                client.matrixMediaLoader.loadMediaContent(largeImage).getOrNull()?.let { bytes ->
                    runCatching {
                        Image.makeFromEncoded(bytes)
                            .encodeToData(EncodedImageFormat.PNG)
                            ?.let { data ->
                                Files.createTempFile("notification_icon_", ".png").toFile().apply {
                                    writeBytes(data.bytes)
                                    deleteOnExit()
                                }
                            }
                    }.onFailure { log.w("Failed to prepare large icon for notification", it) }
                        .getOrNull()
                }
            }
        }
        try {
            sendNotification(
                title = title,
                message = message,
                largeImage = largeIconFile?.path,
                onActivated = { onNotificationActivated(id) },
            )
        } catch (t: Throwable) {
            log.e("Failed to send notification", t)
        }
    }
}
