# android/app/proguard-rules.pro

# Flutter / Embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# （他のネイティブSDKを入れたら、必要に応じてここに keep を追加）
