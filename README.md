# gallformers
The gallformers site

[![type-coverage](https://img.shields.io/badge/dynamic/json.svg?label=type-coverage&prefix=%E2%89%A5&suffix=%&query=$.typeCoverage.atLeast&uri=https%3A%2F%2Fraw.githubusercontent.com%2Fplantain-00%2Ftype-coverage%2Fmaster%2Fpackage.json)](https://github.com/jeffdc/gallformers)

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

All of the images are stored on AWS S3, currently under Jeff's personal account. 

The domains (gallformers.org and gallformers.com) are registered using namecheap and are currently in Jeff's personal account.

The SSL certs are generated and auto-renewed via Let's Encrypt. There is a daemon process on the server that runs the auto-renewal process every 3 months.

### Monitoring
There is a very simple [down detector](lambdas/gallformers_downdetector.js) implemented as an AWS Lambda. The lambda checks the site every 2 minutes to see if it responds with an HTTP 200 response. If the site responds negatively more than once in the span of 5 minutes then an alert is sent out via a message sent from the lambda to AWS SQS to AWS SNS/CloudWatch. The CloudWatch alarm triggers [another lambda](lambdas/snsToSlack.js) that posts a message to the [site-monitoring](https://gallformerdat-m1g8137.slack.com/archives/C01DGA0E9EX) Slack channel and then SNS is used to send an email to Jeff.

There are also several alarms configured on the DO Droplet that hosts the server. These are all resource utilization alarms and will send messages to the [site-monitoring](https://gallformerdat-m1g8137.slack.com/archives/C01DGA0E9EX) Slack channel if triggered.

#### Database Schema Updates (Migrations)
Changes to the schema must involve the following steps:

1. Create a new migration script in [migrations](migrations). It must be named such that it is one larger than the latest.
1. Add all schema changes to the script. There is an `Up` and `Down` sections. The `Up` section is where all of the changes go and then use the `Down` section to undo those changes. This is so that if the `Up` part fails the migration can rollback the changes.
1. Make the schema changes in the [schema.prisma](prisma/schema.prisma) file. These need to match the changes in the migration script.
1. Test, test, test. It is recommend that that you run your `Up` script against a copy of the database to make sure it works as expected.
1. Run `yarn migrate` to execute a migration.
1. Run `yarn generate` to generate a new Prisma client.

Because [yarn is a PITA](https://github.com/yarnpkg/yarn/issues/3630) you will have to temporarily add the following to your dev dependencies for migration to work:
```
    "better-sqlite3": "^7.1.1",
    "better-sqlite3-helper": "^3.1.1",
    "sqlite": "^4.0.15"
```

If you leave them in you will not be able to build with docker as `better-sqlite3` requires python to build and there is no python in the docker container.

### Backup Strategy
TBD. For now manual snapshots of the block volume are all we have. All of the source is on github and the site can be re-created from scratch on a new instance from the files there. The only real back up needed is the database.

### Front-End
The front-end is mostly static pages as we expect most of this data to not change frequently.  next.js is built on [React](https://reactjs.org/) so you will need some familiarity with that to work on the site. The look-and-feel is built with [react-bootstrap](https://react-bootstrap.github.io/). Custom components are placed in the [pages/components](pages/components) directory and global layout components in [pages/layouts](pages/layouts). 

### Production and Staging (non-dev) Deployments
The site is deployed on a Digital Ocean droplet with a mounted volume that contains the database. Details of how to access this etc. are not appropriate for this README.

Currently user management is handled via Auth0. They have a reasonable free-tier that gives us what we need for our current minimal needs. All user management happens via the Auth0 management console. The site is generally meant to be accessed without authentication. Authentication and authorization is only needed for data management/curation features.
