# CLAUDE.md

Fork of [lowlighter/metrics](https://github.com/lowlighter/metrics) — GitHub profile metrics SVG generator.

Upstream is effectively abandoned (last commit Dec 2023). This fork carries custom fixes.

## Architecture

The action runs as a **Docker container** on GitHub Actions. The pipeline:

1. Docker builds a container with Node 22, Chrome's shared libraries, Ruby, Deno, Python
2. `npm ci` installs dependencies, including Puppeteer v25, which downloads its own Chrome
3. The action fetches GitHub data via REST/GraphQL APIs
4. **Puppeteer renders the SVG** using headless Chrome, resizes it, and commits to the repo

### Key files

- `Dockerfile` — Container setup, Chrome + dependency installation
- `source/app/metrics/utils.mjs` — Puppeteer launch config, SVG rendering (`svg.resize`, `svg.pdf`, `svg.hash`)
- `source/app/action/index.mjs` — GitHub Action entrypoint
- `source/app/metrics/index.mjs` — Main metrics generation orchestrator

## Chrome / Puppeteer setup

**Chrome is pinned by `package-lock.json`.** Puppeteer downloads the Chrome for Testing build it was released against during `npm ci`; the browser changes only when Puppeteer is bumped. Until 2026-11 the image instead installed `google-chrome-stable` from apt with the download skipped, which paired Puppeteer 21 (built for Chrome ~116) with whatever Chrome was current — Chrome 156 by then. Don't go back to that: the drift is unbounded and the failure mode is a silent hang at "Rendering".

- `PUPPETEER_CACHE_DIR=/metrics/.cache/puppeteer` is set before `RUN npm ci` so the download and the runtime lookup agree on one fixed path instead of on `HOME`. `action.yml` is a composite action that runs `docker run --env-file .env` itself, and that file carries only `INPUT_*`, `GITHUB*`, `ACTIONS*`, `CI` and `TZ`, so `HOME` is `/root` today; the fixed path keeps it that way if the runner setup changes.
- `PUPPETEER_CHROME_HEADLESS_SHELL_SKIP_DOWNLOAD` skips the second browser: `headless: true` uses full Chrome.
- `PUPPETEER_BROWSER_PATH` is still honoured by `utils.mjs` (`executablePath`) but is unset; setting it overrides the pinned browser.
- The apt list in the Dockerfile is Chrome's shared libraries (from pptr.dev/troubleshooting) plus CJK/Thai/Arabic fonts. The apt `google-chrome-stable` package used to pull the libraries in as dependencies.
- Chrome for Testing has no linux-arm64 build: build locally with `docker build --platform linux/amd64`.

### Puppeteer ≥23 returns `Uint8Array`, not `Buffer`

`page.screenshot()` and `page.pdf()` results are wrapped in `Buffer.from(...)` in `utils.mjs`. The action's output writer (`source/app/action/index.mjs`, `Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value))`) would otherwise write a PNG/PDF as a JSON array of numbers. Wrap any new screenshot call the same way.

### Puppeteer launch flags

These flags in `utils.mjs` prevent hangs in Docker/CI environments:

- `--no-sandbox` — Required in Docker (no user namespace)
- `--disable-dev-shm-usage` — Prevents /dev/shm exhaustion in containers
- `--disable-gpu` — Prevents GPU initialization hangs on Linux
- `--disable-software-rasterizer` — Prevents software rendering hangs
- `--no-first-run` — Skips Chrome first-run setup
- `--no-zygote` — Prevents zygote process issues in containers

### Timeouts

All Puppeteer operations have explicit timeouts to prevent silent hangs:

- `timeout: 60000` on `puppeteer.launch()` — browser must start within 60s
- `protocolTimeout: 120000` — CDP protocol calls timeout after 120s
- `timeout: 60000` on all `page.setContent()` calls — content must load within 60s

Without these, a hung Chrome process causes the entire GitHub Actions job to run until the workflow timeout (15 min) with zero error output.

### waitUntil events

`page.setContent()` uses `["load", "domcontentloaded"]` — **not** `networkidle2`.

Since content is loaded inline via `setContent()` (not navigated to via `goto()`), there is no reason to wait for network activity. Using `networkidle2` caused indefinite hangs when any referenced resource (image, font) failed to resolve.

## Workflow (`supairish/supairish`)

The workflow lives in a **separate repo** (`supairish/supairish/.github/workflows/main.yml`) and references this action by commit SHA:

```yaml
- uses: supairish/metrics@<commit-sha> # master
```

After pushing fixes to this repo, update the SHA in the workflow file.

## Maintenance checklist

When modifying this fork:

- [ ] Keep `PUPPETEER_CACHE_DIR` a fixed path set before the `RUN npm ci` layer; don't reintroduce `PUPPETEER_SKIP_DOWNLOAD` or an apt Chrome
- [ ] Wrap `page.screenshot()` / `page.pdf()` results in `Buffer.from(...)`
- [ ] Keep explicit timeouts on all Puppeteer operations (launch, setContent, evaluate)
- [ ] Don't add `networkidle2` back to `setContent()` waitUntil events
- [ ] After pushing changes, update the commit SHA in `supairish/supairish` workflow
- [ ] Monitor the next scheduled run to verify changes work
