# FROM node:16-alpine as deps
# RUN apk -U upgrade

# WORKDIR /usr/src/app

# create a layer with all the dependencies so that we can rely on the docker cache unless package.json changes
# COPY package.json yarn.lock ./
# RUN yarn set version berry && yarn install 

FROM node:16-alpine as build
WORKDIR /usr/src/app
COPY . .
# COPY --from=deps /usr/src/app/node_modules ./node_modules
# COPY --from=deps /usr/src/app/.yarn ./.yarn
# RUN ls -lA

RUN yarn set version berry && yarn install 

ENV NEXT_TELEMETRY_DISABLED 1
# node modules will be r/o which can cause issues with React and the way it renames stuff at build time so...
# RUN 
# mv ./node_modules ./node_modules.tmp \
	# && mv ./node_modules.tmp ./node_modules \
RUN	yarn generate \
	&& yarn add --dev typescript @types/node \
	&& yarn build \
	&& npm prune --production

# this gets huge and we do not need it for the final build
RUN rm -rf .next/cache
# these are dev tools related to Prisma that are large and not needed in prod
RUN rm node_modules/@prisma/engines/introspection-engine-linux-musl
RUN rm node_modules/@prisma/engines/migration-engine-linux-musl
RUN rm node_modules/@prisma/engines/prisma-fmt-linux-musl

## Shrink final image, copy built nextjs and startup the server
FROM node:16-alpine

WORKDIR /usr/src/app
ENV NODE_ENV production

# copy from build image
COPY --from=build /usr/src/app/package.json /usr/src/app/package.json
COPY --from=build /usr/src/app/node_modules /usr/src/app/node_modules
COPY --from=build /usr/src/app/.next /usr/src/app/.next
COPY --from=build /usr/src/app/public /usr/src/app/public

EXPOSE 3000
CMD ["yarn", "start"]

