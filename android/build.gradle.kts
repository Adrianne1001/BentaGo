allprojects {
    repositories {
        google()
        mavenCentral()
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
// Raises any Android library subproject whose plugin pins an older compileSdk
// than its transitive dependencies require -- the "is currently compiled
// against android-34" build failure. This must be registered before the
// evaluationDependsOn block below, which forces evaluation; afterEvaluate on an
// already-evaluated project is an error.
//
// Only compileSdk moves, which widens the APIs available at compile time.
// minSdk and targetSdk -- device support and runtime behaviour -- are untouched.
subprojects {
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.LibraryExtension &&
            androidExtension.compileSdk != null &&
            androidExtension.compileSdk!! < 36
        ) {
            androidExtension.compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
