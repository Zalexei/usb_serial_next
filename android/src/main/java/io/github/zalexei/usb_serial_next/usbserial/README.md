# Vendored usb-serial-for-android

Source: https://github.com/mik3y/usb-serial-for-android, tag `3.11.0`
(commit 8e694372dee4531d140766df7af3189d3d9531c5), folder
`usbSerialForAndroid/src/main/java/com/hoho/android/usbserial`.

The library is published only on JitPack. It is copied here so that apps using
`usb_serial_next` need no extra Maven repository.

Changes: the Java package `com.hoho.android.usbserial` was renamed to
`io.github.zalexei.usb_serial_next.usbserial`, so the copy cannot clash with
the original library if an app also depends on it. `BuildConfig.java` was
added: the original gets that class from its own Gradle module. Nothing else
was changed.

License: MIT, see LICENSE.txt in this folder.
