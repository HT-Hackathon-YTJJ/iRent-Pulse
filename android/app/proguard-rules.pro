# R8 rules for the release build. Only ever exercised by `flutter build apk
# --release` — debug builds do not run R8 at all, which is why the release
# build was broken for weeks without anybody noticing.

# google_mlkit_text_recognition declares every script ML Kit supports in one
# `initialize` switch — Latin, Chinese, Devanagari, Japanese, Korean — but each
# script's model is a **separate** Gradle dependency and this app only pulls in
# the Latin one (`l0/plate_reader.dart` reads plates). R8 sees the four
# unreferenced branches, cannot resolve their option classes, and fails the
# build.
#
# `-dontwarn` rather than adding the dependencies: the other four models are
# ~15 MB of APK to satisfy branches that are unreachable — the plugin only
# touches them when asked for that script, and nothing here ever does.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit is wired up **reflectively**: the merged manifest carries
# `<meta-data>` entries naming each `ComponentRegistrar`, and ML Kit's
# ComponentDiscovery instantiates them by name through a no-arg constructor at
# startup. R8 sees no caller for those constructors and removes them, so the
# first release build came up logging
#
#   ComponentDiscovery: NoSuchMethodException:
#       com.google.mlkit.vision.text.internal.TextRegistrar.<init> []
#
# — not a crash, just the text recogniser silently never registering, which is
# 車牌比對 quietly not working in every build a colleague would ever install.
# Debug builds do not run R8, so this is invisible until the release build.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
