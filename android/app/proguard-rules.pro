# Firebase / Firestore / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**
