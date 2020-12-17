# docker pull node:current-alpine3.11
FROM node:alpine as build
RUN apk update && apk upgrade

# look at https://gist.github.com/armand1m/b8061bcc9e8e9a5c1303854290c7d61e
# to get yarn caching working to make builds much faster...
WORKDIR /usr/src/app

# create a layer with all the dependencies so that we can rely on the docker cache unless package.json changes
COPY package.json ./
COPY yarn.lock ./

COPY . .

ENV NEXT_TELEMETRY_DISABLED 1
# These layers can't be broken up due to npm not working well with docker layers
RUN yarn install --production=true && \
	npx prisma generate && \
	yarn add --dev typescript @types/node && \
	yarn build && \
	npm prune --production

## Shrink final image, copy built nextjs and startup the server
FROM node:12-alpine

WORKDIR /usr/src/app

# copy from build image
COPY --from=build /usr/src/app/package.json /usr/src/app/package.json
COPY --from=build /usr/src/app/node_modules /usr/src/app/node_modules
COPY --from=build /usr/src/app/.next /usr/src/app/.next
COPY --from=build /usr/src/app/public /usr/src/app/public


EXPOSE 3000
CMD ["yarn", "start"]

