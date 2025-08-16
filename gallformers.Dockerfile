FROM --platform=${BUILD_PLATFORM:-linux/amd64} node:20-slim AS builder
WORKDIR /usr/src/app

# Copy the entire project
COPY ../package.json ../yarn.lock ../.yarnrc.yml ./
COPY ../.yarn ./.yarn
COPY ../prisma ./prisma
COPY ../components ./components
COPY ../hooks ./hooks
COPY ../layouts ./layouts
COPY ../libs ./libs
COPY ../pages ./pages
COPY ../public ./public
COPY ../types ./types
COPY ../next.config.mjs ./
COPY ../tsconfig.json ./

# Enable Corepack and set up Yarn
RUN corepack enable && corepack prepare yarn@4.9.1 --activate

# Install dependencies
RUN yarn install 

ENV NEXT_TELEMETRY_DISABLED 1

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
ENV DATABASE_URL="file:/data/gallformers.sqlite"

# Copy only the necessary files from build
COPY --from=builder /usr/src/app/package.json ./package.json
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/.next ./.next
COPY --from=builder /usr/src/app/public ./public
COPY --from=builder /usr/src/app/prisma ./prisma

# Create data directory and set permissions
RUN mkdir -p /data && \
    chmod 777 /data

EXPOSE 3000

CMD ["node_modules/next/dist/bin/next", "start"]

