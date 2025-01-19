# Keep everything under the main ML Kit text package
-keep class com.google.mlkit.vision.text.** { *; }

# If you want to be more explicit, also keep sub-packages:
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
