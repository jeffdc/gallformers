# docker pull node:current-alpine3.11
FROM node:alpine as build
RUN apk update && apk upgrade

# look at https://gist.github.com/armand1m/b8061bcc9e8e9a5c1303854290c7d61e
# to get yarn caching working to make builds much faster...
WORKDIR /usr/src/app

# create a layer with all the dependencies so that we can rely on the docker cache unless package.jspn changes
COPY package.json ./
COPY yarn.lock ./
# RUN node --stack-size=6000 $(which npm) --verbose install
RUN yarn install 

# copy all the stuff
COPY . .

# generate the prisma client, then run the build which will generate the static site and all other assets
ENV NEXT_TELEMETRY_DISABLED 1
RUN NODE_OPTIONS="--max_old_space_size=1024 --report-on-fatalerror" npx prisma generate && yarn add --dev typescript @types/node && yarn build
# prune reduces the image some bits more :)
RUN npm prune --production


## Shrink final image, copy built nextjs and startup the server
FROM node:12-alpine

WORKDIR /usr/src/app

# copy from build image
COPY --from=build /usr/src/app/package.json /usr/src/app/package.json
COPY --from=build /usr/src/app/node_modules /usr/src/app/node_modules
# COPY --from=build /usr/src/app/prisma /prisma
COPY --from=build /usr/src/app/.next /usr/src/app/.next
COPY --from=build /usr/src/app/public /usr/src/app/public


EXPOSE 3000
CMD ["yarn", "start"]

