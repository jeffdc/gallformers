SERVICE_NAME := gallformers

.PHONY: build
build: 
	docker build -t $(SERVICE_NAME):latest .

run: 
	docker run -it $(SERVICE_NAME):latest