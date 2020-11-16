SERVICE_NAME := gallformers

.PHONY: build
build: 
	docker build

.PHONY: run-local
run-local:
	docker run -v "/usr/src/data:prisma/" --env-file .env.local --name $(SERVICE_NAME) -p 3000:3000 -d $(SERVICE_NAME):latest
	docker start $(SERVICE_NAME)

.PHONY: save-image
save-image:
	## TODO move to publish to repo - as this is, a manual step of copying the tar to the server is required.
	docker save $(SERVICE_NAME):latest > $(SERVICE_NAME)-docker.tar

.PHONY: run
run: 
	sudo docker stop $(SERVICE_NAME)
	sudo docker rm $(SERVICE_NAME)
	## TODO this is not the step we really want, should pull new image from repo
	sudo docker load < $(SERVICE_NAME)-docker.tar
	sudo docker run -v "/usr/src/data:/mnt/gallformers_data" --env-file .env --name $(SERVICE_NAME) -p 3000:3000 -d $(SERVICE_NAME):latest
	sudo docker start $(SERVICE_NAME)


# this is for getting the server setup initially
.PHONY: bootstrap
bootstrap:
	sudo apt-get install haveged
	sudo update-rc.d haveged defaults

	sudo ufw allow 80
	sudo ufw allow 443
	sudo ufw enable

	sudo apt-get install nginx-full
	sudo ln -s nginx/nginx.conf /etc/nginx/conf.d/nginx.conf
	
	sudo install core
	sudo snap refresh core

	sudo snap install --classic certbot
	sudo ln -s /snap/bin/certbot /usr/bin/certbot	
	
	# gets the certs and installs them changing the nginx configuration
	sudo certbot --nginx

	# copy the database to the mounted volume
	sudo cp prisma/gallformers.sqlite /mnt/gallformers_data 
	