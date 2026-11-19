# Rules for the release build, which R8 shrinks and optimizes.
#
# WorkManager (a transitive dependency) builds its Room database by reflection
# when the app starts (androidx.startup). R8 sees no direct use of the
# generated WorkDatabase_Impl and made it impossible to instantiate: the
# release APK closed on launch with "Failed to create an instance of
# androidx.work.impl.WorkDatabase". Keep every Room database with its
# constructor.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
