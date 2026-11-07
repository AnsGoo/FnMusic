import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.compose.multiplatform)
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    // The model module is a plain JVM library, so the same domain types back
    // both clients. Its Android-only coroutine dispatcher is excluded: the
    // desktop runtime would fail to classify it.
    implementation(project(":core:model")) {
        exclude(group = "org.jetbrains.kotlinx", module = "kotlinx-coroutines-android")
    }

    implementation(compose.desktop.currentOs)
    implementation(compose.material3)

    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.swing)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.okhttp)
    // javax.sound has no MP3 decoder; the server transcodes every request to
    // MP3, so this SPI is all the audio stack needs.
    implementation(libs.mp3spi)

    testImplementation(libs.junit)
}

tasks.test {
    // The live-server test is opt-in: forward the credentials the developer
    // exported for this shell, if any. Without them the test self-skips.
    listOf("FNMUSIC_TEST_SERVER", "FNMUSIC_TEST_USER", "FNMUSIC_TEST_PASSWORD", "FNMUSIC_SHOTS", "FNMUSIC_AUDIO_TEST")
        .forEach { key -> System.getenv(key)?.let { environment(key, it) } }
}

compose.desktop {
    application {
        mainClass = "com.seasonyuu.fnmusic.desktop.MainKt"

        nativeDistributions {
            targetFormats(TargetFormat.Dmg)
            packageName = "FnMusic"
            packageVersion = "1.0.0"
            description = "Music Free 桌面客户端"
            vendor = "FnMusic"
            macOS {
                bundleID = "com.seasonyuu.fnmusic.desktop"
                dockName = "FnMusic"
                iconFile.set(project.file("icons/app.icns"))
                // The desktop build targets Apple silicon; Intel Macs would need
                // a second packaging pass with an x64 JDK.
                minimumSystemVersion = "12.0"
            }
        }
    }
}
