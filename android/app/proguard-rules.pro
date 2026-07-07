# mobile_scanner / ML Kit 用反射，R8 full mode 会误删
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
