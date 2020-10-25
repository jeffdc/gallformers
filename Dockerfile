# docker pull node:current-alpine3.11
FROM node:alpine
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
RUN npx prisma generate && yarn build

EXPOSE 3000
CMD ["yarn", "start"]

# RUN apk --update add nginx
