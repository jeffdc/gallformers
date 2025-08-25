# Gallformers Scripts (Python Version)

This directory contains Python scripts for managing the Gallformers application.

## Setup

1. Create a virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Create a `.env` file with the following variables:
```
BACKUP_BUCKET=your-backup-bucket-name
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=your-region
```

## Available Tasks

### Backup
Creates a backup of the database and uploads it to S3.
```bash
python main.py backup
```

### Restore
Restores a database backup from S3.
```bash
python main.py restore <backup-key>
```

### Setup
Sets up the initial database and configuration.
```bash
python main.py setup
```

## Project Structure

- `main.py` - Entry point for all tasks
- `tasks/` - Task implementations
- `utils/` - Utility functions and helpers
- `config/` - Configuration and environment setup
- `tests/` - Test files

## Development

To add a new task:

1. Create a new file in the `tasks/` directory
2. Implement a class with an `execute()` method
3. Add the task to the registry in `main.py`

## Testing

Run tests with:
```bash
python -m pytest tests/
``` 