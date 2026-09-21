package chat.fleunce

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import chat.fleunce.ui.FleunceTheme
import chat.fleunce.ui.OnboardingScreen
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LargeTypeOnboardingTest {
    @get:Rule val compose = createComposeRule()
    @Test fun bothDropdownStepsRemainUsableAtDoubleTextSize() {
        var selected: Pair<String, String>? = null
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, 2f)) {
                FleunceTheme { OnboardingScreen("es", "English") { language, meaning -> selected = language to meaning } }
            }
        }
        compose.onNodeWithTag("onboarding-language-picker").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("onboarding-continue").assertIsDisplayed().performClick()
        compose.onNodeWithTag("onboarding-meaning-picker").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("onboarding-continue").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals("es" to "English", selected) }
    }
}
