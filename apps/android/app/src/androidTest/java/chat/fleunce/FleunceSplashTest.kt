package chat.fleunce

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import chat.fleunce.ui.FleunceSplash
import chat.fleunce.ui.FleunceStartup
import chat.fleunce.ui.FleunceTheme
import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FleunceSplashTest {
    @get:Rule val compose = createComposeRule()

    @Test fun localHistoryGatesContentAndCompletedStartupSurvivesRecreation() {
        val loading = mutableStateOf(true)
        val restoration = StateRestorationTester(compose)
        restoration.setContent { FleunceTheme {
            FleunceStartup(loading.value, minimumDurationMillis = 0) {
                Text("Ready", Modifier.testTag("startup-content"))
            }
        } }
        compose.onNodeWithTag("fleunce-splash").assertIsDisplayed()
        compose.onNodeWithTag("startup-content").assertDoesNotExist()
        compose.runOnIdle { loading.value = false }
        compose.waitUntil { compose.onAllNodesWithTag("startup-content").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("fleunce-splash").assertDoesNotExist()
        compose.runOnIdle { loading.value = true }
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("startup-content").assertIsDisplayed()
        compose.onNodeWithTag("fleunce-splash").assertDoesNotExist()
    }

    @Test fun splashContainsOnlyTheOrbAndItsPulseChangesTheRenderedFrame() {
        val phase = mutableStateOf(0f)
        compose.setContent { FleunceTheme { FleunceSplash(phaseOverride = phase.value) } }
        compose.onNodeWithTag("fleunce-splash").assertIsDisplayed()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.Text)).assertCountEquals(0)
        compose.onAllNodes(hasClickAction()).assertCountEquals(0)
        val resting = capture("splash-orb-rest.png")
        compose.runOnIdle { phase.value = .62831855f }
        val expanded = capture("splash-orb-pulse.png")
        assertFalse("The pulse must visibly change the orb", resting.sameAs(expanded))
    }

    @Test fun compactWindowKeepsTheOrbCenteredAndInsideTheSplash() {
        compose.setContent { FleunceTheme {
            Box(Modifier.size(320.dp, 180.dp)) { FleunceSplash(phaseOverride = 0f) }
        } }
        val splash = compose.onNodeWithTag("fleunce-splash").fetchSemanticsNode().boundsInRoot
        val orb = compose.onNodeWithTag("fleunce-splash-orb", useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(orb.left > splash.left && orb.right < splash.right)
        assertTrue(orb.top > splash.top && orb.bottom < splash.bottom)
        assertEquals(splash.center.x, orb.center.x, 1f)
        assertEquals(splash.center.y, orb.center.y, 1f)
    }

    private fun capture(name: String): Bitmap {
        val bitmap = compose.onNodeWithTag("fleunce-splash").captureToImage().asAndroidBitmap()
        val directory = File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir, "splash-review").apply { mkdirs() }
        File(directory, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return bitmap
    }
}
