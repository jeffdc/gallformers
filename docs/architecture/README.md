# Gallformers Architecture

This directory contains C4 model architecture diagrams for Gallformers V2.

**Quick Start**: See [QUICKSTART.md](QUICKSTART.md) for viewing and editing instructions.

## C4 Model

The [C4 model](https://c4model.com/) by Simon Brown provides a hierarchical way to visualize software architecture at different levels of detail:

1. **System Context (C1)** - Shows how the system fits in the world (external dependencies, users)
2. **Container (C2)** - Shows the high-level technical building blocks (apps, databases, services)
3. **Component (C3)** - Shows the major components within a container (Phoenix contexts)
4. **Code (C4)** - Shows implementation details (not included - too detailed)

## Viewing Diagrams

The architecture is defined in [`workspace.dsl`](workspace.dsl) using Structurizr DSL. This single file generates all C4 diagrams plus a deployment view.

**Quick start:**

```bash
cd docs/architecture
./view.sh
# Open http://localhost:8080
```

**To export static images:**

```bash
# Install Structurizr CLI
brew install structurizr-cli

# Export all diagrams to PNG
cd docs/architecture
structurizr-cli export -workspace workspace.dsl -format png

# Or SVG for better quality
structurizr-cli export -workspace workspace.dsl -format svg
```

## What's Included

The workspace defines four diagrams:

1. **System Context (C1)** - Gallformers and its external dependencies (Auth0, S3, users)
2. **Containers (C2)** - Runtime components (Phoenix app, database, GenServers)
3. **Components (C3)** - Phoenix contexts and their relationships
4. **Deployment** - Production infrastructure on Fly.io and AWS

## Updating the Architecture

When the architecture changes:

1. **Update the DSL**: Edit `workspace.dsl` (single source of truth)
2. **Regenerate exports** (optional): Run Structurizr CLI to export new images
3. **Update Mermaid** (optional): Sync changes to `.md` files if needed for GitHub preview

The DSL is version-controlled, so you can see how the architecture evolved over time.
