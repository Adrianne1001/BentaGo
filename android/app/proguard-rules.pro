# Flutter's engine is reached from native code, so R8 cannot see the references
# and would otherwise strip these.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# sqflite and path_provider go through platform channels, same reasoning.
-keep class com.tekartik.sqflite.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }

# Keep annotations R8 uses to decide what is reachable.
-keepattributes *Annotation*

# Flutter's engine references Play Core for deferred components (downloading
# feature modules on demand). This app is a single APK and never uses them, so
# the classes are legitimately absent and R8 should not treat that as an error.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
