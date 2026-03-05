# CLAUDE.md

Fork of [lowlighter/metrics](https://github.com/lowlighter/metrics) — GitHub profile metrics SVG generator.

Upstream is effectively abandoned (last commit Dec 2023). This fork carries custom fixes.

## Architecture

The action runs as a **Docker container** on GitHub Actions. The pipeline:

1. Docker builds a container with Node 20, system Chrome, Ruby, Deno, Python
2. `npm ci` installs dependencies (including Puppeteer v21)
3. The action fetches GitHub data via REST/GraphQL APIs
4. **Puppeteer renders the SVG** using headless Chrome, resizes it, and commits to the repo

### Key files

- `Dockerfile` — Container setup, Chrome + dependency installation
- `source/app/metrics/utils.mjs` — Puppeteer launch config, SVG rendering (`svg.resize`, `svg.pdf`, `svg.hash`)
- `source/app/action/index.mjs` — GitHub Action entrypoint
- `source/app/metrics/index.mjs` — Main metrics generation orchestrator

## Critical: Dockerfile ENV ordering

`ENV` directives only apply to **subsequent** `RUN` instructions. The `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD` and `PUPPETEER_SKIP_DOWNLOAD` vars **must** be set before `RUN npm ci`, or Puppeteer will download a ~200MB Chromium binary on every build (wasting time and causing intermittent hangs).

```dockerfile
# CORRECT — ENV before RUN
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
ENV PUPPETEER_SKIP_DOWNLOAD true
RUN npm ci

# WRONG — ENV after RUN (has no effect during build)
RUN npm ci
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD true
```

## Chrome / Puppeteer setup

- **System Chrome** (`google-chrome-stable`) is installed via apt-get in the Dockerfile
- **Puppeteer's bundled Chromium download is skipped** — we use the system Chrome instead
- `PUPPETEER_BROWSER_PATH="google-chrome-stable"` tells Puppeteer which binary to use
- Puppeteer v21 was built for Chromium ~117, but system Chrome updates independently — version drift is possible

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

- [ ] Never move `PUPPETEER_SKIP_DOWNLOAD` ENV after the `RUN npm ci` layer
- [ ] Keep explicit timeouts on all Puppeteer operations (launch, setContent, evaluate)
- [ ] Don't add `networkidle2` back to `setContent()` waitUntil events
- [ ] After pushing changes, update the commit SHA in `supairish/supairish` workflow
- [ ] Monitor the next scheduled run to verify changes work
