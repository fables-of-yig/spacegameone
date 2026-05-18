# Third-Party Licenses

This project bundles third-party code under permissive open-source licenses. The
full upstream license texts are preserved alongside the vendored sources.

## PixelPlanets

- Location: `Space/vendor/pixel_planets/`
- Upstream: https://github.com/Deep-Fold/PixelPlanets
- License: MIT (see `Space/vendor/pixel_planets/UPSTREAM_LICENSE`)
- Copyright (c) 2020 Deep-Fold

Used in the SpaceboatMania content editor to render and bake authored astral
bodies (planets, stars, anomalies). All upstream shaders and scripts are
preserved under `Space/vendor/pixel_planets/` with their original folder
structure; only resource paths were rewritten from `res://Planets/` to
`res://Space/vendor/pixel_planets/` so the code lives under our `Space/` tree
without colliding with the project root namespace.
