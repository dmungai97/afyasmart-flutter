import java.util.Properties

// Local, gitignored values such as the Mapbox token (see secrets.properties.example).
val secretProperties = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = (project.findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?)
                    ?: (project.findProperty("mapboxApiKey") as String?)
                    ?: secretProperties.getProperty("mapboxApiKey")
                    ?: ""
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// mapbox_maps_flutter only applies kotlin-android when AGP < 9, assuming AGP 9's
// built-in Kotlin otherwise. gradle.properties opts out of built-in Kotlin
// (android.builtInKotlin=false), so on AGP 9 the plugin ends up with no Kotlin
// at all and its `kotlin { }` block fails. Other plugins (firebase_core etc.)
// check that flag; Mapbox does not, so apply the Kotlin plugin for it here,
// as soon as it applies com.android.library and before its kotlin block runs.
// Remove once Mapbox honours android.builtInKotlin.
subprojects {
    if (name == "mapbox_maps_flutter") {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
