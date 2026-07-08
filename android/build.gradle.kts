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
subprojects {
    project.evaluationDependsOn(":app")
}

// Some Flutter plugins (file_picker, share_plus) still ship with an old
// compileSdk, while flutter_plugin_android_lifecycle requires 36+. Force a
// uniform compileSdk across every plugin module.
subprojects {
    fun forceCompileSdk(p: Project) {
        (p.extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileSdkVersion(36)
    }
    // evaluationDependsOn(":app") above means some projects are already
    // evaluated by the time this block runs — handle both cases.
    if (state.executed) forceCompileSdk(this) else afterEvaluate { forceCompileSdk(this) }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
