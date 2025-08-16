# FROM node:16-alpine as deps
# RUN apk -U upgrade

# WORKDIR /usr/src/app

# create a layer with all the dependencies so that we can rely on the docker cache unless package.json changes
# COPY package.json yarn.lock ./
# RUN yarn set version berry && yarn install 

FROM --platform=${BUILD_PLATFORM:-linux/amd64} node:20-slim AS builder
WORKDIR /usr/src/app
COPY . .
# COPY --from=deps /usr/src/app/node_modules ./node_modules
# COPY --from=deps /usr/src/app/.yarn ./.yarn
# RUN ls -lA

# Enable Corepack and set up Yarn
RUN corepack enable && corepack prepare yarn@4.9.1 --activate

# Install dependencies
RUN yarn install 

ENV NEXT_TELEMETRY_DISABLED 1
# node modules will be r/o which can cause issues with React and the way it renames stuff at build time so...
# RUN 
# mv ./node_modules ./node_modules.tmp \
# && mv ./node_modules.tmp ./node_modules \

# RUN	yarn generate \
# 	&& yarn add --dev typescript @types/node \
# 	&& yarn build \
# 	&& npm prune --omit=dev

ENV DATABASE_URL="file:/usr/src/app/prisma/gallformers.sqlite"

# Build the application and run migrations
RUN yarn generate && \
    yarn add --dev typescript @types/node && \
    yarn build && \
    # Remove development files and caches
    rm -rf .next/cache && \
    rm -rf node_modules/.cache && \
    # Remove development dependencies and clean up
    yarn workspaces focus --production && \
    rm -rf node_modules/@prisma/engines/*linux-musl && \
    rm -rf node_modules/.yarn && \
    rm -rf node_modules/.cache && \
    # Remove unnecessary npm files
    find node_modules -name "*.md" -delete && \
    find node_modules -name "*.ts" -delete && \
    find node_modules -name "*.map" -delete && \
    find node_modules -name "LICENSE" -delete && \
    find node_modules -name "CHANGELOG.md" -delete && \
    find node_modules -name "README.md" -delete

## Final stage
FROM --platform=${BUILD_PLATFORM:-linux/amd64} node:20-slim

# Install SQLite and other necessary dependencies
RUN apt-get update && \
    apt-get install -y sqlite3 openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Copy only the necessary files from build
COPY --from=builder /usr/src/app/package.json ./package.json
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/.next ./.next
COPY --from=builder /usr/src/app/public ./public
COPY --from=builder /usr/src/app/prisma ./prisma

# Ensure proper permissions
RUN chmod 644 /usr/src/app/prisma/gallformers.sqlite

EXPOSE 3000

CMD ["node_modules/next/dist/bin/next", "start"]

