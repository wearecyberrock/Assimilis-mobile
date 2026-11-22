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

subprojects {
    if (project.name != "app") {
        // Older plugins pin compileSdk 30-33 and Java/Kotlin 1.8; their AndroidX
        // dependencies need compileSdk >= 34. Raise them once their DSL is final.
        pluginManager.withPlugin("com.android.library") {
            extensions.getByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>()
                .finalizeDsl { android ->
                    if ((android.compileSdk ?: 0) < 36) {
                        android.compileSdk = 36
                    }
                    android.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                    android.compileOptions.targetCompatibility = JavaVersion.VERSION_17
                }
        }
        // Registered after the plugin's own build script so JVM 17 wins over
        // plugins that hard-code jvmTarget 1.8 (Java is raised to 17 above).
        afterEvaluate {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
