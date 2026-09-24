# Flutter core classes
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.app.** { *; }

# Keep third-party Flutter plugin classes

# Suppress warnings for common missing classes
-dontwarn org.conscrypt.**
-dontwarn org.w3c.dom.bootstrap.DOMImplementationRegistry
