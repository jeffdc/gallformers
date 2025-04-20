"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const backup_1 = __importDefault(require("./tasks/backup"));
const restore_1 = __importDefault(require("./tasks/restore"));
const setup_1 = __importDefault(require("./tasks/setup"));
const logger_1 = __importDefault(require("./utils/logger"));
const tasks = {
    backup: backup_1.default,
    restore: restore_1.default,
    setup: setup_1.default,
};
async function main() {
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
    }
    catch (error) {
        logger_1.default.error('Task failed', {
            task: taskName,
            error: error instanceof Error ? error.message : String(error),
        });
        process.exit(1);
    }
}
if (require.main === module) {
    void main().catch((error) => {
        console.error('Unhandled error:', error);
        process.exit(1);
    });
}
