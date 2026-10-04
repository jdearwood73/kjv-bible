#!/usr/bin/env python3
"""Run from the repo root after `flutter create`. Sets the app name, icon, link permissions and (when
android/key.properties exists) release signing. Safe to run more than once."""
import pathlib, re, shutil, sys

root = pathlib.Path(".")
android = root / "android"
manifest = android / "app/src/main/AndroidManifest.xml"

# --- app name + queries (lets the app open web links) ---
m = manifest.read_text()
m = re.sub(r'android:label="[^"]*"', 'android:label="KJV Bible"', m, count=1)
if "<queries>" not in m:
    m = m.replace("<application", '''<queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="mailto" />
        </intent>
    </queries>
    <application''', 1)
manifest.write_text(m)

# --- icons ---
for d in (root / "icon").glob("mipmap-*"):
    dest = android / "app/src/main/res" / d.name
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy(d / "ic_launcher.png", dest / "ic_launcher.png")
# drop adaptive-icon overrides from the template so the PNGs are used
for p in (android / "app/src/main/res").glob("mipmap-anydpi*"):
    shutil.rmtree(p, ignore_errors=True)

# --- signing ---
if (android / "key.properties").exists():
    kts = android / "app/build.gradle.kts"
    groovy = android / "app/build.gradle"
    if kts.exists():
        s = kts.read_text()
        if "keystoreProperties" not in s:
            s = ("import java.util.Properties\nimport java.io.FileInputStream\n\n" + s)
            s = s.replace("android {", '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {''', 1)
            s = s.replace("buildTypes {", '''signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {''', 1)
            s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                       'signingConfig = signingConfigs.getByName("release")', s)
            kts.write_text(s)
    elif groovy.exists():
        s = groovy.read_text()
        if "keystoreProperties" not in s:
            s = '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

''' + s
            s = s.replace("buildTypes {", '''signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {''', 1)
            s = s.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
            groovy.write_text(s)
    else:
        sys.exit("no android/app/build.gradle(.kts) found")
    print("signing configured")
