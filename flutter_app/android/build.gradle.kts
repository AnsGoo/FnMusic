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
// device_info_plus 9.1.2 的 android 模块把 compileSdkVersion 写死成 33，而它依赖的
// androidx 组件（lifecycle-process 2.7、annotation-experimental 1.4 等）要求 34+，
// AGP 会直接判构建失败（依赖要求 compileSdk 34 或更高）。
// 这里在子工程（含所有插件模块）评估完成后把 compileSdk 抬到 36 —— 只影响编译期
// 可见的 API，不动 targetSdk / minSdk，运行时行为不变。
//
// 两个注意点：
//   * 必须注册在下面 evaluationDependsOn(":app") 之前：那句会提前把子工程评估掉，
//     之后再加 afterEvaluate 会报 "project is already evaluated"。
//   * 走反射而不是强类型：根工程的脚本 classpath 不含 AGP，直接引用 LibraryExtension
//     编译不过。AGP 9 的 setter 是 setCompileSdk(Int)，老版本是 compileSdkVersion(Int)
//     或 setCompileSdkVersion(String)，三种都试一遍。
val overrideCompileSdk = 36
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        var applied = false
        for (m in androidExt.javaClass.methods) {
            if (m.parameterTypes.size != 1) continue
            val type = m.parameterTypes[0]
            val arg: Any? =
                when {
                    type == Int::class.javaPrimitiveType &&
                        (m.name == "setCompileSdk" || m.name == "compileSdkVersion") -> overrideCompileSdk
                    type == String::class.java && m.name == "setCompileSdkVersion" -> overrideCompileSdk.toString()
                    else -> null
                }
            if (arg == null) continue
            try {
                m.invoke(androidExt, arg)
                applied = true
                break
            } catch (e: Exception) {
                // 继续尝试下一个候选方法
            }
        }
        logger.lifecycle("MusicFly: compileSdk -> $overrideCompileSdk on :${project.name} (applied=$applied)")
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
