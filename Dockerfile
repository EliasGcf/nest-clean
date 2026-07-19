FROM node:20-bookworm-slim AS deps

WORKDIR /opt/app

ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH

RUN corepack enable && corepack prepare pnpm@8.15.9 --activate
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile && \
    pnpm store prune && \
    rm -rf ~/.local/share/pnpm/store ~/.cache/pnpm

COPY prisma ./prisma
RUN pnpm prisma generate

FROM deps AS build

COPY nest-cli.json tsconfig*.json ./
COPY src ./src
RUN pnpm build

FROM deps AS prod-deps

RUN pnpm prune --prod && \
    pnpm store prune && \
    rm -rf ~/.local/share/pnpm/store ~/.cache/pnpm

FROM node:20-bookworm-slim AS runner

WORKDIR /opt/app

ENV NODE_ENV=production
ENV PORT=3333

LABEL io.openshift.expose-services="3333:http" \
      io.openshift.tags="nodejs,nestjs" \
      io.openshift.min-memory="128Mi" \
      io.openshift.min-cpu="100m"

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=prod-deps /opt/app/package.json ./package.json
COPY --from=prod-deps /opt/app/node_modules ./node_modules
COPY --from=build /opt/app/dist ./dist
COPY --from=build /opt/app/prisma ./prisma

RUN chgrp -R 0 /opt/app && \
    chmod -R g=u /opt/app

EXPOSE 3333
USER 1001

CMD ["node", "dist/infra/main"]
