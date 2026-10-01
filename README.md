# Morph Simulator

Mix the head, body and legs of 100 animals across 10 maps.

- **Play in the browser** (desktop or iPad): `web/public/` — a static Three.js + Rapier game, served by Render (see `render.yaml`).
- **Mac app**: native Swift + SceneKit in `Sources/`. Build with `./build.sh` (Xcode Command Line Tools) → `Morph Simulator.app`.
  Self-test: `"Morph Simulator.app/Contents/MacOS/MorphSimulator" --autotest`. Trailer: `--trailer DIR` renders frames + audio.wav.
- `web/public/mac.html` is the Mac download page with the trailer; the zip there is the built app.
