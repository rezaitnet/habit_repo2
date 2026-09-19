import os, re

manifest = "android/app/src/main/AndroidManifest.xml"
s = open(manifest, encoding="utf-8").read()
perms = ('    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
         '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n')
recv = '''        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
'''
if "POST_NOTIFICATIONS" not in s:
    s = s.replace("<application", perms + "    <application", 1)
    s = s.replace("</application>", recv + "    </application>", 1)
open(manifest, "w", encoding="utf-8").write(s)

kts = "android/app/build.gradle.kts"
grv = "android/app/build.gradle"
if os.path.exists(kts):
    g = open(kts, encoding="utf-8").read()
    g = g.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, "w", encoding="utf-8").write(g)
else:
    g = open(grv, encoding="utf-8").read()
    g = g.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(grv, "w", encoding="utf-8").write(g)
print("patched")
