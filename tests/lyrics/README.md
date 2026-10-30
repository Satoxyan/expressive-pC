# Lyrics tests

Run from the repo root:

```sh
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qmltestrunner -import tests/lyrics -input tests/lyrics
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
  /usr/lib/qt6/bin/qml -I tests/lyrics tests/lyrics/render.qml
```

`render.qml` grabs the karaoke widget mid-line to `/tmp/lyrics-render.png`
(the path is hardcoded — `QImageWriter` takes the file suffix as the image
format, so saving to `…png.tmp` fails silently). The widget is drawn as a
host-sized 400x150 box inside a 420x210 window with the media widget's own
settings — `lineContext: 2` and `clipOverflowY: -1`, which takes the vertical
cut out — so anything that reaches past the 150px strip is drawn in the
padding instead of sliced.
`QT_ASSUME_STDERR_HAS_CONSOLE=1` is what keeps `console.log` on the terminal
instead of the journal.

`qs/` is a test-only module tree: the real `Lyrics.qml` and `StyledText.qml`
reached through a `qmldir`, plus a stub `Appearance`, a stub
`MaterialLoadingIndicator` and a scriptable `LyricsService` double the tests
push line/word state into.

Caveats:

- A word that is at least partly lit sits behind the glow layer, and a layer is
  a `ShaderEffect`: an offscreen grab renders it as nothing, which would drop
  the whole active line out of the PNG. `render.qml` therefore sets
  `glowEnabled: false` and measures the white fill, which is a plain clip. How
  the glow itself reads can only be judged in a real Quickshell session.
- `Item.visible` reads false for every item in an offscreen `qmltestrunner` run
  (the window is never exposed), so the tests assert widths and colours, never
  visibility.
