# gallformers
The gallformers site

## Getting Started
You must have [npm](https://www.npmjs.com/get-npm) and yarn installed for any of this to work. Go do that. I highly recommend using a node version manager of some kind.
Installing yarn is easy once you have npm:
```bash
npm install -g yarn
```

Get setup:
```bash
yarn install
npx prisma generate
```

You will need to run `generate` again if the DB [schema](prisma/schema.prisma) is changed.

Now you can run the development server:
```bash
yarn dev
```
Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can build and run the prod version of the site:
```bash
yarn build
yarn start
```
To run in the docker container:
```bash
make build
make run-local
```
This should now make the site accessible on your local machine at [http://localhost:3000](http://localhost:3000)

You can also create a tar of the docker image by running:
```
make save-image
```

The other commands are meant to be used on the server (at least until we get some deployment automation in place).

## Technical Overview
The whole site is built using [next.js](nextjs.org/). 

### Back-end and Database
The datastore is a [sqlite](https://sqlite.org/index.html) database. The schema can be seen in the [initial migration script](migrations/001-gallformers.sql). There is a copy of the DB committed to the repo for ease of testing etc. The prod database is on a volume attached to the server.

The APIs for accessing the data from the front-end are implemented in [Prisma](https://www.prisma.io/) and are all called from the server (either statically rendered at build time or rendered on request if they could not be build statically, e.g., the search results).

#### Database Schema Upates (Migrations)
Changes to the schema must involve the follwoing steps:

1. Create a new migration script in [migrations](migrations). It must be named such that it is one larger than the latest.
1. Add all schema changes to the script. There is an `Up` and `Down` sections. The `Up` section is where all of the changes go and then use the `Down` section to undo those changes. This is so that if the `Up` part fails the migration can rollback the changes.
1. Make the schema changes in the [schema.prisma](prisma/schema.prisma) file. These need to match the changes in the migration script.
1. Test, test, test. It is recommend that that you run your `Up` script against a copy of the database to make sure it works as expected.
1. Run `yarn migrate` to execute a migration.
1. Run `yarn generate` to generate a new Prisma client.

### Backup Strategy
TBD. For now manual snapshots of the block volume are all we have. All of the source is on github and the site can easily be re-created from scratch on a new instance from the files there. The only real back up needed is the database.

### Front-End
The front-end is mostly static pages as we expect most of this data to not change frequently.  next.js is built on [React](https://reactjs.org/) so you will need some familiarity with that to work on the site. The look-and-feel is built with [react-bootstrap](https://react-bootstrap.github.io/). Custom components are placed in the [pages/components](pages/components) directory and global layout components in [pages/layouts](pages/layouts). 

### Production and Staging (non-dev) Deployments
The site is deployed on a Digital Ocean droplet with a mounted volume that contains the database. Details of how to access this etc. are not appropriate for this README.

Currently user management is handled via Auth0. They have a reasonable free-tier that gives us whta we need for our current minimal needs. All user management happens via the Auth0 management console. The site is generally meant to be accessed with authentication. Authentication and authorization is only needed for data management/curation features.