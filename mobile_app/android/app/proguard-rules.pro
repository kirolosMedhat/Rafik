# Flutter Engine & Embeddings
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class com.rafik.** { *; }

# Flutter Plugins and Registrant
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.**
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }

# Kotlin & Coroutines
-keepattributes *Annotation*,InnerClasses,EnclosingMethod,Signature
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# Google Sign In & Play Services
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.**

# OkHttp & WebSockets (used by Supabase/Realtime)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
