"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const child_process_1 = require("child_process");
const util_1 = require("util");
const logger_1 = __importDefault(require("../utils/logger"));
const env_1 = __importDefault(require("../config/env"));
const execAsync = (0, util_1.promisify)(child_process_1.exec);
class SetupTask {
    async execute() {
        try {
            // Load environment variables
            env_1.default.load();
            logger_1.default.info('Starting development environment setup');
            // Check Node.js version
            const { stdout: nodeVersion } = await execAsync('node --version');
            logger_1.default.info('Node.js version', { version: nodeVersion.trim() });
            // Enable corepack
            logger_1.default.info('Enabling corepack');
            await execAsync('corepack enable');
            // Install dependencies
            logger_1.default.info('Installing dependencies');
            await execAsync('yarn install');
            // Setup Prisma
            logger_1.default.info('Setting up Prisma');
            await execAsync('yarn prisma generate');
            // Create necessary directories
            logger_1.default.info('Creating necessary directories');
            await execAsync('mkdir -p logs backups');
            // Setup PM2
            logger_1.default.info('Setting up PM2');
            await execAsync('pm2 install pm2-logrotate');
            await execAsync('pm2 set pm2-logrotate:max_size 10M');
            await execAsync('pm2 set pm2-logrotate:retain 7');
            logger_1.default.info('Development environment setup completed successfully');
            return { success: true };
        }
        catch (error) {
            logger_1.default.error('Setup failed', { error: error instanceof Error ? error.message : String(error) });
            throw error;
        }
    }
}
// If running directly (not imported as a module)
if (require.main === module) {
    new SetupTask().execute().catch((error) => {
        console.error('Setup failed:', error);
        process.exit(1);
    });
}
exports.default = SetupTask;
