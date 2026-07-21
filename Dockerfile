# syntax=docker/dockerfile:1

# =============================================================================
# wacrm — Next.js 16 + Supabase, built for Dokploy
#
# Multi-stage build using Next.js standalone output (see next.config.ts).
# pnpm is the package manager (pnpm-lock.yaml), enabled via corepack.
#
# NEXT_PUBLIC_* values are inlined into the client bundle at BUILD time,
# so they must be passed as build args (Dokploy: "Build-time Variables").
# Server-only secrets (SERVICE_ROLE_KEY, ENCRYPTION_KEY, META_APP_SECRET)
# are read at RUNTIME — set them as regular environment variables instead.
# =============================================================================

# ---- Base -------------------------------------------------------------------
FROM node:22-alpine AS base
# libc compat for some native deps
RUN apk add --no-cache libc6-compat
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable && corepack prepare pnpm@11.15.1 --activate
WORKDIR /app

# pnpm 11 supply-chain gates, relaxed for a reproducible CI build. pnpm only
# reads these from pnpm-workspace.yaml (not .npmrc / env), and any pnpm call
# (install, and the implicit deps-check before `pnpm build`) needs them — so
# we generate the file once here in the shared base stage:
#   - minimumReleaseAge: 0  -> allow just-published deps in the pinned lockfile
#                              (else ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION)
#   - strictDepBuilds: false -> don't fail the install over unrun native
#                              postinstall scripts (else ERR_PNPM_IGNORED_BUILDS;
#                              sharp & co. ship prebuilt binaries via optional deps)
#   - onlyBuiltDependencies -> approve the native postinstall scripts we do want
RUN printf '%s\n' \
    'minimumReleaseAge: 0' \
    'strictDepBuilds: false' \
    'onlyBuiltDependencies:' \
    '  - "@parcel/watcher"' \
    '  - "@swc/core"' \
    '  - sharp' \
    '  - unrs-resolver' \
    > pnpm-workspace.yaml

# ---- Dependencies -----------------------------------------------------------
FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile

# ---- Builder ----------------------------------------------------------------
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build-time public env (inlined into the client bundle).
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY
ARG NEXT_PUBLIC_SITE_URL
ARG NEXT_PUBLIC_APP_LOCALE
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL \
    NEXT_PUBLIC_APP_LOCALE=$NEXT_PUBLIC_APP_LOCALE \
    NEXT_TELEMETRY_DISABLED=1

RUN pnpm build

# ---- Runner -----------------------------------------------------------------
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# Run as an unprivileged user.
RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 nextjs

# Standalone server + traced node_modules, static assets and public files.
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
