package chat.schildi.revenge.actions

import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import chat.schildi.lib.util.OperatingSystem
import chat.schildi.lib.util.SystemInfo

private val isMacOs = SystemInfo.getOs() == OperatingSystem.Mac

/**
 * Ctrl, or Cmd on macOS: keybindings are specified with `ctrl`, which should map to the platform's
 * primary shortcut modifier.
 */
val KeyEvent.isPrimaryModifierPressed: Boolean
    get() = isCtrlPressed || (isMacOs && isMetaPressed)

val KeyEvent.isOnlyShiftPressed: Boolean
    get() = isShiftPressed && !isCtrlPressed && !isAltPressed && !isMetaPressed
val KeyEvent.isOnlyCtrlPressed: Boolean
    get() = isPrimaryModifierPressed && !isShiftPressed && !isAltPressed && (isMacOs || !isMetaPressed)
val KeyEvent.isNoModifierPressed: Boolean
    get() = !isShiftPressed && !isCtrlPressed && !isAltPressed && !isMetaPressed
