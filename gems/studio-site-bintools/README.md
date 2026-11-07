# studio-site-bintools

CI, lint and image scripts for studio Bridgetown marketing sites, run as `bin/studio <script>`. Rails apps use [studio-app-bintools](../studio-app-bintools).

```sh
bin/studio                         # list scripts
bin/studio help optimize-images   # usage, also <script> --help
bin/studio ci
bin/studio optimize-images --check
```

| Script | Does |
| --- | --- |
| `ci` | lint, npm audit, fingerprint check, then a production build |
| `lint` / `style` | checks / fixes ERB with herb |
| `outdated` | reports outdated gems and npm packages |
| `check-fingerprinted-images` | fails when an image path bypasses esbuild fingerprinting |
| `optimize-images [--check \| --prune] [file ...]` | encodes sources to .webp within config/images.yml bounds |

optimize-images needs ImageMagick (`magick`) and libwebp (`cwebp`). `--check` fails on a missing or stale .webp without writing anything.

## Setup

Add `gem "studio-site-bintools"` to the toolshed block in the Gemfile, then from the site root:

```sh
bundle exec studio install
```

This adds bin/studio, and copies bin/setup if the site has none; the site owns it after that. New scripts arrive with `bundle update studio-site-bintools`.

## config/images.yml

```yaml
quality: 82
default_max_width: 1600

sources:
  - src/assets/images
  - frontend/images

rules:
  - match: og-image.png              # basename, or a path when it has a /
    skip: true
  - match: frontend/images/screenshots/*
    max_width: 1400
    max_height: 900

fingerprinting:                                        # all optional
  raw_path_prefixes: [/assets/images/, /screenshots/]  # default [/assets/images/]
  allowed_raw_paths: [/assets/images/blog/*]           # globs
  allowed_unwrapped_expressions: ['\bbadges\.']        # regexes for <img src="<%= ... %>">
```

`/assets/images/og-image*` and `/assets/images/favicon/*` are always allowed.

## Adding a script

Put it in `libexec/`, executable, with a `# Summary:` line under the shebang, and a `# Usage:` line under that if it takes arguments. bin/studio answers `--help` itself, so the script never sees it, unless the script is listed in `OWN_HELP`. It runs from the site root.
