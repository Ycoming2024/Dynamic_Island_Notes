import org.gradle.api.artifacts.repositories.MavenArtifactRepository

allprojects {
    repositories {
        maven(url = "https://storage.flutter-io.cn/download.flutter.io")
        maven(url = "https://storage.googleapis.com/download.flutter.io")
        maven(url = "https://maven.aliyun.com/repository/gradle-plugin")
        maven(url = "https://maven.aliyun.com/repository/google")
        maven(url = "https://maven.aliyun.com/repository/public")
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
    buildscript {
        repositories {
            maven(url = "https://storage.flutter-io.cn/download.flutter.io")
            maven(url = "https://storage.googleapis.com/download.flutter.io")
            maven(url = "https://maven.aliyun.com/repository/gradle-plugin")
            maven(url = "https://maven.aliyun.com/repository/google")
            maven(url = "https://maven.aliyun.com/repository/public")
            google()
            mavenCentral()
        }
    }

    repositories {
        maven(url = "https://storage.flutter-io.cn/download.flutter.io")
        maven(url = "https://storage.googleapis.com/download.flutter.io")
        maven(url = "https://maven.aliyun.com/repository/gradle-plugin")
        maven(url = "https://maven.aliyun.com/repository/google")
        maven(url = "https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
    }

    buildscript.repositories.withType(MavenArtifactRepository::class.java).configureEach {
        val raw = url.toString()
        if (raw.contains("repo.maven.apache.org") || raw.contains("repo1.maven.org")) {
            setUrl("https://maven.aliyun.com/repository/public")
        }
    }

    repositories.withType(MavenArtifactRepository::class.java).configureEach {
        val raw = url.toString()
        if (raw.contains("repo.maven.apache.org") || raw.contains("repo1.maven.org")) {
            setUrl("https://maven.aliyun.com/repository/public")
        }
    }

    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
