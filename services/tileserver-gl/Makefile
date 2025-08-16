.PHONY: build-boundaries build-docker run-local deploy clean stop

# Variables
DOCKER_IMAGE := gftiles
FLY_APP := gftiles
BOUNDARIES_FILE := boundaries.mbtiles

# Build the boundaries.mbtiles file if it doesn't exist
build-boundaries:
	@if [ ! -f "$(BOUNDARIES_FILE)" ]; then \
		echo "Building boundaries.mbtiles..."; \
		chmod +x build_boundaries.sh; \
		./build_boundaries.sh $(BOUNDARIES_FILE); \
	else \
		echo "boundaries.mbtiles already exists, skipping build..."; \
	fi

# Build the Docker container
build-docker: $(BOUNDARIES_FILE)
	@echo "Building Docker container..."
	@docker build -t $(DOCKER_IMAGE) -f tileserver-gl.Dockerfile .

# Run the container locally
run-local: build-docker
	@echo "Running container locally..."
	@docker run -it --rm -p 8080:8080 $(DOCKER_IMAGE)

# Stop the local container
stop:
	@echo "Stopping local container..."
	@docker stop $$(docker ps -q --filter ancestor=$(DOCKER_IMAGE)) 2>/dev/null || true

# Deploy to fly.io
deploy:
	@echo "Deploying to fly.io..."
	@fly deploy

# Clean up generated files
clean:
	@echo "Cleaning up..."
	@rm -f $(BOUNDARIES_FILE)
	@docker rmi $(DOCKER_IMAGE) || true

# Help target
help:
	@echo "Available targets:"
	@echo "  build-boundaries  - Build the boundaries.mbtiles file if it doesn't exist"
	@echo "  build-docker     - Build the Docker container"
	@echo "  run-local        - Run the container locally"
	@echo "  stop             - Stop the local container"
	@echo "  deploy           - Deploy to fly.io"
	@echo "  clean            - Clean up generated files"
	@echo "  help             - Show this help message" 