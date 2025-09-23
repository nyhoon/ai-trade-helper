# Flutter 관련 규칙
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 백그라운드 서비스 관련 규칙
-keep class com.dexterous.** { *; }
-keep class androidx.work.** { *; }
-keep class androidx.startup.** { *; }

# flutter_background_service 관련 규칙
-keep class com.example.trade_app_new_clean.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }

# SharedPreferences 관련 규칙
-keep class android.content.SharedPreferences { *; }

# 네트워크 관련 규칙
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }

# JSON 관련 규칙
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# 일반적인 Android 규칙
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# SQLite 관련 규칙
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }

# 권한 관련 규칙
-keep class com.baseflow.permissionhandler.** { *; }

# 알림 관련 규칙
-keep class androidx.core.app.** { *; }
-keep class android.app.** { *; }

# 기타 필요한 규칙들
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
