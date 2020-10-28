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
docker build -t gallformers:latest .
docker run --name gallformers -p 3002:3000 -d gallformers:latest <-- from previous step
docker start gallformers
```
This should now make the site accessible on your local machine at [http://localhost:3002](http://localhost:3002)

## Technical Overview
The whole site is built using [next.js](nextjs.org/). 

### Back-end and Database
The datastore is a [sqlite](https://sqlite.org/index.html) database. The schema can be seen in the [initial migration script](migrations/001-gallformers.sql). The actual DB is committed to the repo. When the server starts the migrations are run. The initial data load was taken from a bunch of CSV files that were exported out of AirTable. The schema from AirTable was very wonky so the [script](data_from_airtable/genSQLfromCSV.py) to import the CSVs is a mess. Once we get a satisfactory initial load this code should no longer be needed and can deleted along with the CSV files.

The APIs for accessing the data from the front-end are implemented in [Prisma](https://www.prisma.io/) and are all called from the server (either statically rendered at build time or rendered on request if they could not be build statically, e.g., the search results).

There is a totally separate data curation step that is not discussed here.  The gallformers.sqlite DB that is on the main branch in this repo is the current production data.

### Front-End
The front-end is mostly static pages as we expect most of this data to not change frequently.  next.js is built on [React](https://reactjs.org/) so you will need some familiarity with that to work on the site. The look-and-feel is built with [react-bootstrap](https://react-bootstrap.github.io/). Custom components are placed in the [pages/components](pages/components) directory and global layout components in [pages/layouts](pages/layouts). 

### Production and Staging (non-dev) Deployments
TODO
