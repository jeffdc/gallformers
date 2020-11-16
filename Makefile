SERVICE_NAME := gallformers

.PHONY: build
build: 
	docker build

.PHONY: run-local
run-local:
	docker run -v "/usr/src/data:prisma/" --env-file .env.local --name $(SERVICE_NAME) -p 3000:3000 -d $(SERVICE_NAME):latest
	docker start $(SERVICE_NAME)

.PHONY: stop
stop:
	docker stop $(SERVICE_NAME)

.PHONY: restart-local
restart-local: stop run-local

# TODO move to publish to repo - as this is, a manual step of copying the tar to the server is required.
.PHONY: save-image
save-image:
	docker save $(SERVICE_NAME):latest > $(SERVICE_NAME)-docker.tar

.PHONY: run
run: 
	docker run -v "/usr/src/data:/mnt/gallformers_data" --env-file .env --name $(SERVICE_NAME) -p 3000:3000 \
		        -d $(SERVICE_NAME):latest
	docker start $(SERVICE_NAME)

.PHONY: restart
restart: stop run

# TODO this is not the step we really want, should pull new image from repo
.PHONY: load-image
load-image: stop
	docker rm $(SERVICE_NAME)
	docker load < $(SERVICE_NAME)-docker.tar



# this is for getting the server setup initially
.PHONY: bootstrap
bootstrap:
	apt-get install haveged
	update-rc.d haveged defaults

	ufw allow 80
	ufw allow 443
	ufw enable

	apt-get install nginx-full
	ln -s nginx/nginx.conf /etc/nginx/conf.d/nginx.conf

	install core
	snap refresh core

	snap install --classic certbot
	ln -s /snap/bin/certbot /usr/bin/certbot	
	
	# gets the certs and installs them changing the nginx configuration
	certbot --nginx

	# copy the database to the mounted volume
	cp prisma/gallformers.sqlite /mnt/gallformers_data 
	