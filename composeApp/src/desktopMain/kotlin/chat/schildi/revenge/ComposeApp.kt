package chat.schildi.revenge

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.toRect
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowDecoration
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import chat.schildi.lib.util.OperatingSystem
import chat.schildi.lib.util.SystemInfo
import chat.schildi.revenge.model.GlobalUnreadCountsSource
import chat.schildi.revenge.model.spaces.SpaceAggregationDataSource
import chat.schildi.revenge.preferences.RevengePrefs
import chat.schildi.theme.ScTheme
import chat.schildi.theme.prefersDarkTheme
import chat.schildi.lib.preferences.ScPrefs
import chat.schildi.revenge.preferences.value
import chat.schildi.revenge.actions.KeyboardActionHandler
import chat.schildi.revenge.actions.LocalKeyboardActionHandler
import chat.schildi.revenge.compose.WindowContent
import chat.schildi.revenge.compose.components.LocalWindowDiagnostics
import chat.schildi.revenge.compose.components.WindowDiagnostics
import chat.schildi.revenge.compose.components.rememberScaledDensity
import chat.schildi.revenge.compose.media.LocalImageLoaderHolder
import chat.schildi.revenge.dbus.TrayWatcher
import chat.schildi.revenge.model.verification.RevengeDeviceVerificationProvider
import chat.schildi.revenge.notification.SyncingNotificationProcessor
import chat.schildi.revenge.notification.DesktopNotifier
import coil3.PlatformContext
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.painterResource
import shire.res.generated.resources.Res
import shire.res.generated.resources.ic_launcher
import java.awt.Desktop
import java.awt.GraphicsEnvironment
import java.awt.Taskbar
import java.awt.desktop.AppReopenedListener
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent

@OptIn(ExperimentalComposeUiApi::class)
object ComposeApp {
    private val isMac = SystemInfo.getOs() == OperatingSystem.Mac

    // Height of the macOS titlebar that the app content is extended underneath
    private val macTitlebarInset = 28.dp

    /**
     * macOS dock integration: clicking the dock icon while the app is hidden (close to tray)
     * brings the window back, and the dock icon badge shows the notified chat count.
     */
    @Composable
    private fun MacDockIntegration() {
        DisposableEffect(Unit) {
            val desktop = runCatching { Desktop.getDesktop() }.getOrNull()
            val supported = desktop?.isSupported(Desktop.Action.APP_EVENT_REOPENED) == true
            val listener = AppReopenedListener { UiState.setMinimized(false) }
            if (supported) {
                desktop?.addAppEventListener(listener)
            }
            onDispose {
                if (supported) {
                    desktop?.removeAppEventListener(listener)
                }
            }
        }
        val notifiedChats = GlobalUnreadCountsSource.globalUnreadCounts
            .collectAsState(SpaceAggregationDataSource.SpaceUnreadCounts()).value.notifiedChats
        LaunchedEffect(notifiedChats) {
            runCatching {
                val taskbar = Taskbar.getTaskbar()
                if (taskbar.isSupported(Taskbar.Feature.ICON_BADGE_TEXT)) {
                    taskbar.setIconBadge(notifiedChats.takeIf { it > 0 }?.toString())
                }
            }
        }
    }

    /**
     * Make the macOS titlebar match the app theme, and let the app background extend under it
     * (transparent "unified" titlebar). Content needs [macTitlebarInset] top padding then.
     */
    private fun java.awt.Window.applyMacTitlebar(dark: Boolean) {
        val root = (this as? javax.swing.RootPaneContainer)?.rootPane ?: return
        root.putClientProperty(
            "apple.awt.windowAppearance",
            if (dark) "NSAppearanceNameDarkAqua" else "NSAppearanceNameAqua",
        )
        root.putClientProperty("apple.awt.fullWindowContent", true)
        root.putClientProperty("apple.awt.transparentTitleBar", true)
    }

    fun main(startInTray: Boolean, initialCommand: String? = null) {
        SdkLoader.ensureLoaded()
        TrayWatcher.start()
        SyncingNotificationProcessor.observeNotifications()
        RevengeDeviceVerificationProvider.observe()
        application(exitProcessOnExit = false) {
            // Blocking initialization
            remember {
                UiState.initializeWith(
                    exitApplication = { this@application.exitApplication() },
                    startInTray = startInTray,
                )
            }
            if (isMac) {
                MacDockIntegration()
            }
            LaunchedEffect(Unit) {
                RevengePrefs.prefetch()
                DesktopNotifier.initialize()
                if (initialCommand != null) {
                    UiState.headlessKeyboardActionHandler?.executeCommandFromIpc(initialCommand)
                }
            }
            val minimized = UiState.minimizedToTray.collectAsState().value
            key(UiState.trayIconRecreationCounter.collectAsState().value) {
                TrayIcon(isMinimized = minimized, setMinimized = UiState::setMinimized)
            }
            key(UiState.forceRecreationCounter.collectAsState().value) {
                if (!minimized) {
                    val windows = platformWindowManager.windows.collectAsState().value
                    windows.forEach { windowState ->
                        key(windowState.windowId) {
                            val destinationState = windowState.destinationHolder.state.collectAsState().value
                            val title = destinationState.titleOverride?.render()
                                ?: destinationState.destination.title?.render()
                                ?: DEFAULT_WINDOW_APP_TITLE.render()
                            // The default window height (1200) exceeds many laptop screens, which on macOS
                            // leaves the window partly off-screen: never exceed the usable screen area
                            val usableScreen = remember {
                                runCatching { GraphicsEnvironment.getLocalGraphicsEnvironment().maximumWindowBounds }.getOrNull()
                            }
                            val initialWidth = ScPrefs.INITIAL_WINDOW_WIDTH.value()
                                .let { w -> if (isMac && usableScreen != null) minOf(w, usableScreen.width) else w }
                            val initialHeight = ScPrefs.INITIAL_WINDOW_HEIGHT.value()
                                .let { h -> if (isMac && usableScreen != null) minOf(h, usableScreen.height) else h }
                            val composeWindowState = rememberWindowState(
                                size = DpSize(
                                    initialWidth.dp,
                                    initialHeight.dp,
                                )
                            )
                            val hideDecoration = remember {
                                runBlocking {
                                    RevengePrefs.getSetting(ScPrefs.HIDE_WINDOW_DECORATION)
                                }
                            }
                            val scope = rememberCoroutineScope()
                            val keyHandler = remember {
                                KeyboardActionHandler(PlatformContext.INSTANCE, scope, windowState.windowId)
                            }
                            Window(
                                state = composeWindowState,
                                onCloseRequest = {
                                    UiState.closeWindow(windowState.windowId)
                                },
                                title = title,
                                icon = painterResource(Res.drawable.ic_launcher),
                                onPreviewKeyEvent = keyHandler::onPreviewKeyEvent,
                                onKeyEvent = keyHandler::onKeyEvent,
                                transparent = hideDecoration,
                                decoration = if (hideDecoration)
                                    WindowDecoration.Undecorated()
                                else
                                    WindowDecoration.SystemDefault,
                            ) {
                                // LocalFocusManager and LocalClipboard are not set outside the Window composable
                                val focusManager = LocalFocusManager.current
                                val clipboard = LocalClipboard.current
                                val uriHandler = LocalUriHandler.current
                                if (isMac && !hideDecoration) {
                                    val darkTitlebar = prefersDarkTheme()
                                    LaunchedEffect(window, darkTitlebar) { window.applyMacTitlebar(darkTitlebar) }
                                }
                                LaunchedEffect(keyHandler, focusManager) { keyHandler.focusManager = focusManager }
                                LaunchedEffect(keyHandler, clipboard) { keyHandler.clipboard = clipboard }
                                LaunchedEffect(keyHandler, uriHandler) { keyHandler.uriHandler = uriHandler }

                                // Scaling settings
                                val rootDensity = LocalDensity.current
                                val localDensity = rememberScaledDensity()

                                DisposableEffect(window) {
                                    val listener = object : WindowAdapter() {
                                        override fun windowGainedFocus(e: WindowEvent) {
                                            keyHandler.onWindowFocusChanged(true)
                                        }

                                        override fun windowLostFocus(e: WindowEvent) {
                                            keyHandler.onWindowFocusChanged(false)
                                        }
                                    }

                                    window.addWindowFocusListener(listener)

                                    onDispose {
                                        window.removeWindowFocusListener(listener)
                                        keyHandler.onWindowFocusChanged(false)
                                    }
                                }
                                LaunchedEffect(keyHandler, composeWindowState.size) {
                                    keyHandler.windowCoordinates = rootDensity.run {
                                        composeWindowState.size.toSize().toRect()
                                    }
                                }
                                CompositionLocalProvider(
                                    LocalImageLoaderHolder provides UiState.appGraph.imageLoaderHolder,
                                    LocalKeyboardActionHandler provides keyHandler,
                                    LocalDensity provides localDensity,
                                    LocalWindowDiagnostics provides remember(window) { WindowDiagnostics.from(window) },
                                ) {
                                    key(UiState.currentLocale.collectAsState().value) {
                                        if (isMac && !hideDecoration) {
                                            // Fill the strip behind the transparent titlebar with the app background
                                            ScTheme {
                                                Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surface)) {
                                                    WindowContent(
                                                        windowState.destinationHolder,
                                                        modifier = Modifier.padding(top = macTitlebarInset),
                                                    )
                                                }
                                            }
                                        } else {
                                            WindowContent(windowState.destinationHolder)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
