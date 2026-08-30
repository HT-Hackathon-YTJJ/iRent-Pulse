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
// tflite_flutter 的 Android module 只設了 Java 11，沒設對應的 Kotlin jvmTarget，
// Kotlin 2.4 於是套用 JDK 的預設值，兩邊對不起來整包就編不過。plugin 不歸我們維護，
// 所以在這裡把所有子專案統一拉到跟 app 一樣的 17。
//
// 兩個位置很講究：
//   * 要用 afterEvaluate——plugin 自己的 android { } 區塊在評估時才跑，
//     在那之前設的值會被它蓋掉。
//   * 這段要排在下面 evaluationDependsOn(":app") 之前——那一行會把 :app 評估完，
//     之後再對 :app 呼叫 afterEvaluate 會直接丟例外。
//
// 拿掉這段之前，先跑一次 `flutter build apk --debug` 確認 plugin 已經自己修好。
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            if (android is com.android.build.api.dsl.CommonExtension) {
                android.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                android.compileOptions.targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
