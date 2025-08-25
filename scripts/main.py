#!/usr/bin/env python3

import sys
from typing import Dict, Type, Any
from tasks.backup import BackupTask
from tasks.restore import RestoreTask
from tasks.setup import SetupTask
from tasks.refresh_staging import RefreshStagingTask
from tasks.set_secrets import SetSecretsTask
from utils.logger import logger

# Task registry
tasks: Dict[str, Type[Any]] = {
    'backup': BackupTask,
    'restore': RestoreTask,
    'setup': SetupTask,
    'refresh-staging-from-latest-backup': RefreshStagingTask,
    'set-secrets': SetSecretsTask,
}

async def main() -> None:
    if len(sys.argv) < 2:
        print('Usage: python main.py <task> [args...]')
        print('Available tasks:', ', '.join(tasks.keys()))
        sys.exit(1)

    task_name = sys.argv[1]
    task_args = sys.argv[2:]

    if task_name not in tasks:
        print(f'Error: Unknown task "{task_name}"')
        print('Available tasks:', ', '.join(tasks.keys()))
        sys.exit(1)

    try:
        task = tasks[task_name]()
        result = await task.execute(task_args[0] if task_args else None)
        print('Task completed successfully:', result)
    except Exception as error:
        logger.error('Task failed', task=task_name, error=str(error))
        sys.exit(1)

if __name__ == '__main__':
    import asyncio
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print('\nTask interrupted by user')
        sys.exit(1)
    except Exception as error:
        print('Unhandled error:', error)
        sys.exit(1) 