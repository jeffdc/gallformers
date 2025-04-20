import BackupTask from './tasks/backup.js';
import RestoreTask from './tasks/restore.js';
import SetupTask from './tasks/setup.js';
import logger from './utils/logger.js';
import { fileURLToPath } from 'url';

interface Task {
    execute(args: unknown): Promise<unknown>;
}

type TaskConstructor = new () => Task;

const tasks: Record<string, TaskConstructor> = {
    backup: BackupTask,
    restore: RestoreTask,
    setup: SetupTask,
};

async function main(): Promise<void> {
    const taskName = process.argv[2];
    const taskArgs = process.argv.slice(3);

    if (!taskName || !tasks[taskName]) {
        console.error('Usage: node index.js <task> [args...]');
        console.error('Available tasks:', Object.keys(tasks).join(', '));
        process.exit(1);
    }

    try {
        const task = new tasks[taskName]();
        const result = await task.execute(taskArgs[0]);
        console.log('Task completed successfully:', result);
    } catch (error) {
        logger.error('Task failed', {
            task: taskName,
            error: error instanceof Error ? error.message : String(error),
        });
        process.exit(1);
    }
}

if (import.meta.url === fileURLToPath(process.argv[1])) {
    void main().catch((error) => {
        console.error('Unhandled error:', error);
        process.exit(1);
    });
}
