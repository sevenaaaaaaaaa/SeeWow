import org.gradle.kotlin.dsl.withGroovyBuilder

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
    val previewNdk = providers.gradleProperty("seewowNdkVersion").orNull
    if (previewNdk != null) {
        // Native plugins may explicitly assign Flutter's default NDK too.
        // Apply the local override after their DSL has been evaluated.
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder {
                setProperty("ndkVersion", previewNdk)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
