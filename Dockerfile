FROM node:alpine as build
RUN apk update && apk upgrade

# look at https://gist.github.com/armand1m/b8061bcc9e8e9a5c1303854290c7d61e
# to get yarn caching working to make builds much faster...
WORKDIR /usr/src/app

# create a layer with all the dependencies so that we can rely on the docker cache unless package.jspn changes
COPY package.json ./
COPY yarn.lock ./
RUN yarn install 

# copy all the stuff
COPY . .

# generate the prisma client, then run the build which will generate the static site and all other assets
RUN npx prisma generate && yarn add --dev typescript @types/node && yarn build
# prune reduces the image some bits more :)
RUN npm prune --production


## Shrink final image, copy built nextjs and startup the server
FROM node:12-alpine

WORKDIR /usr/src/app

# copy from build image
COPY --from=build /usr/src/app/package.json /package.json
COPY --from=build /usr/src/app/node_modules /node_modules
COPY --from=build /usr/src/app/prisma /prisma
COPY --from=build /usr/src/app/.next /.next
COPY --from=build /usr/src/app/public /public


EXPOSE 3000
CMD ["yarn", "start"]

