# Scroll tests

Run from the repo root:

```sh
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner -import tests/scroll -input tests/scroll
QT_QPA_PLATFORM=offscreen qml6 -I tests/scroll tests/scroll/jumpduringfling.qml
QT_QPA_PLATFORM=offscreen qml6 -I tests/scroll tests/scroll/wheelflag.qml
```

Use `/usr/lib/qt6/bin/qmltestrunner`; `/usr/bin/qmltestrunner` is a different build.

`qs/modules/common` is a test-only module: the real `InertialScrollEngine.qml`
and `ContentPage.qml`, plus a stub `Config.qml` with only the scrolling knobs
the engine reads and a stub `Appearance.qml` with only the properties the
widgets read.
