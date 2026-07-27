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

// image_cropper 9.1.0's own android/build.gradle hardcodes compileSdkVersion 33,
// which is too old for its own transitive androidx deps (window, core,
// exifinterface) that require 34+. Force every Android library subproject to
// compile against 36 so the AAR metadata check passes. Must be registered
// before evaluationDependsOn below forces eager evaluation.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
            it.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
