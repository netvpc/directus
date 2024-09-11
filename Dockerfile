# syntax=docker/dockerfile:1.10

FROM node:lts-bookworm AS builder

WORKDIR /directus

RUN \
    apt-get update \
    && apt-get -y --no-install-recommends install tini \
    && git clone --recurse-submodules -j8 --depth 1 https://github.com/directus/directus.git /directus \
    && corepack enable \
    && corepack prepare \
    && pnpm fetch \
    && pnpm install --recursive --offline --frozen-lockfile \
    && npm_config_workspace_concurrency=1 pnpm run build \
    && pnpm --filter directus deploy --prod dist \
    && cd dist \
    && find . -mindepth 1 -maxdepth 1 -name '.*' ! -name '.' ! -name '..' -exec bash -c 'echo "Deleting {}"; rm -rf {}' \; \
    && mkdir -p database extensions uploads \
    && { \
        echo 'const f = "package.json", {name, version, type, exports, bin} = require(`./${f}`), {packageManager} = require(`../${f}`);'; \
        echo 'fs.writeFileSync(f, JSON.stringify({name, version, type, exports, bin, packageManager}, null, 2));'; \
    } | node -e "$(cat)" 

FROM node:lts-bookworm-slim AS runtime

ENV \
    USER=directus \
    UID=1001 \
    GID=1001 \
	DB_CLIENT="sqlite3" \
	DB_FILENAME="/directus/database.sqlite" \
	NODE_ENV="production" \
	NPM_CONFIG_UPDATE_NOTIFIER="false"

WORKDIR /directus

RUN groupadd --gid ${GID} ${USER} \
  && useradd --uid ${UID} --gid ${GID} --home-dir /directus/ --shell /bin/bash ${USER} \
  && chown -R ${UID}:${GID} /directus/

COPY --link --from=builder --chown=${UID}:${GID} /directus/dist /directus/
COPY --link --from=builder --chown=${UID}:${GID} /usr/bin/tini /usr/bin/tini

USER ${USER}

EXPOSE 8055

ENTRYPOINT ["tini", "--"]

CMD node /directus/cli.js bootstrap && node /directus/cli.js start