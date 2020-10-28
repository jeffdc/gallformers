SERVICE_NAME := gallformers

.PHONY: build
build: 
	docker-compose build

run: 
	docker-compose up gallformers