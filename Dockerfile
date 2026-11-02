# Base image
FROM node:22-bookworm-slim

# Puppeteer downloads the Chrome build it was released with during `npm ci`, so the browser
# is pinned by package-lock.json. A fixed cache dir keeps the browser where Puppeteer looks
# for it regardless of HOME at runtime. Only full Chrome is used (headless: true), so skip
# chrome-headless-shell.
ENV PUPPETEER_CACHE_DIR /metrics/.cache/puppeteer
ENV PUPPETEER_CHROME_HEADLESS_SHELL_SKIP_DOWNLOAD true

# Copy repository
COPY . /metrics
WORKDIR /metrics

# Setup
RUN chmod +x /metrics/source/app/action/index.mjs \
  # Install Chrome's shared libraries and fonts to support major charsets
  # Based on https://pptr.dev/troubleshooting#chrome-doesnt-launch-on-linux
  && apt-get update \
  && apt-get install -y wget ca-certificates fonts-liberation libasound2 libatk-bridge2.0-0 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgbm1 libgcc1 libglib2.0-0 libgtk-3-0 libnspr4 libnss3 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 xdg-utils \
    fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-kacst fonts-freefont-ttf lsb-release --no-install-recommends \
  # Install deno for miscellaneous scripts
  && apt-get install -y curl unzip \
  && curl -fsSL https://deno.land/x/install/install.sh | DENO_INSTALL=/usr/local sh \
  # Install ruby to support github licensed gem
  && apt-get install -y ruby-full git g++ cmake pkg-config libssl-dev xz-utils \
  && gem install licensed \
  # Install python for node-gyp
  && apt-get install -y python3 \
  # Clean apt/lists
  && rm -rf /var/lib/apt/lists/* \
  # Install node modules and rebuild indexes
  && npm ci \
  && npm run build

# Execute GitHub action
ENTRYPOINT node /metrics/source/app/action/index.mjs
