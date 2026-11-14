# App icon

`FileerIcon.png` is the current Fileer artwork, supplied by the user, with the surrounding white background removed.
`scripts/build-icon.py` converts it to a full-size macOS ICNS iconset before signing. The rendered artwork is kept
as supplied rather than applying additional Icon Composer glass effects.

The original Strata `AppIcon.icon` and `AppIcon.icns` remain in this directory as the previous editable icon and its
fallback. They were contributed by [RemoPro](https://github.com/RemoPro) in
[issue #12](https://github.com/cristipufu/strata-files/issues/12).
