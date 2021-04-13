# Gallformers Deployment Runbook

## Before you Begin

To execute this runbook you will need to have the following:

* A dev environment. See the main [README](../README.md)
* SSH access to the prod server (yeah, yeah I know)
* sudo access on the prod server (yeah I REALLY know)
* sqlite3 installed locally if you need to apply database schema changes

## Build and Deploy

All steps assume that there were no errors. If you encounter an error then look at the Troubleshooting section below.

**On your dev machine:**
1) `git checkout main`
1) `git pull origin main`
1) `make build`
1) `make save-image`
1) `ssh your-user-name@server-ip`

**Once you have SSHed to the server:**
1) `cd dev/gallformers/`
1) `git pull origin main`
1) `rm gallformers-docker-XXXXXXXX.tar` Delete the old - 1 image, where XXXXXXXX is the date of the old image e.g., 20210412
1) `mv gallformers-docker.tar gallformers-docker-XXXXXXX.tar` rename the previous image, where XXXXXXXX is today's date

**Back on your dev machine:**

Copy the new image to the server: 
1) `scp gallformers-docker.tar your-user-name@server-ip:dev/gallformers/`

**On the server once the copy has completed:**

Put the server in maintenace mode:
1) `sudo cp maintenance.html /var/www/html`

### If there are database changes to be made

I recommend copying the database down locally to your dev machine and applying schema changes there as it is easier to debug etc. if something weird happens.

**On your dev machine**
1) **MAKE SURE you put the site in maintenance mode as mentioned above**
1) Make sure you are in the `gallformers` project dir
1) `scp you-user-name@server-ip:/mnt/gallformers_data/prisma/gallformers.sqlite prisma`

This copies the latest to the prisma folder in the gallformers project.

Apply schema changes:
1) `sqlite3 prisma/gallformers.sqlite`
1) `.echo on`  so you can watch the changes be applied
1) `.read migrations/XXX-gallformers.sql`  where XXX is the number of the latest migration script
1) `.exit`
1) Commit the changes to the repo, you will need a branch and then a PR unless you are repo admin. This is not strictly required but it is nice to have the latest copy of the data in the repo. If you do not do this then the instructions in the next section would be different and are not currently provided.

**On the server:**
1) `sudo cp /mnt/gallformers_data/prisma /mnt/gallformers_data/prisma_XXXXXXXX` creates a backup of the previous database state, use the data rather than the XXXXXXXX as described above
1) `sudo rm -rf /mnt/gallformers_data/prisma`
1) `git pull origin main`  this will get the updated database that you committed earlier
1) `sudo cp prisma /mnt/gallformers_data`

### If there are no database changes or you have already completed any database changes

**On the server**
1) `sudo make redeploy-and-run`  this will stop the docker container, deploy the new one, and restart
1) `sudo rm /var/www/html/maintenance.html`  take the site out of maintenance mode
1) Check the site to make sure it all looks good

## Troubleshooting

### Unwinding Changes

TODO