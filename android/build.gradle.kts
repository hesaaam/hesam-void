allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Xray core used by flutter_v2ray. The plugin asks for libv2ray v26.10.17,
// but Xray 26.9.9 and newer refuse VLESS/Trojan without TLS to public
// servers, which breaks common plain-WebSocket panel profiles. v26.8.20 is
// the newest AndroidLibXrayLite build on Xray 26.7.28, the last core without
// that restriction, and exposes the same binding API.
// Review this pin whenever flutter_v2ray is upgraded.
val xrayCoreRevision = "v26.8.20"
allprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.github.2dust" && requested.name == "libv2ray") {
                useVersion(xrayCoreRevision)
                because("Xray 26.7.28 still accepts plain VLESS/Trojan profiles")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
