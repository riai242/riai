// android/build.gradle.kts  ← 全置換

import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete

plugins {
    // ★ バージョンは書かない（settings.gradle 等の pluginManagement に任せる）
    id("com.android.application") apply false
    id("com.android.library")     apply false
    id("org.jetbrains.kotlin.android") apply false
}

// ここに ext.kotlin_version などの Groovy 断片は置かない

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// （任意・Flutterテンプレ互換のビルド出力先まとめ）
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
