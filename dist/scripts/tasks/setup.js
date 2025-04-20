import { exec } from 'child_process';
import { promisify } from 'util';
import logger from '../utils/logger.js';
import env from '../config/env.js';
const execAsync = promisify(exec);
class SetupTask {
    async execute() {
        try {
            // Load environment variables
            env.load();
            logger.info('Starting development environment setup');
            // Check Node.js version
            const { stdout: nodeVersion } = await execAsync('node --version');
            logger.info('Node.js version', { version: nodeVersion.trim() });
            // Enable corepack
            logger.info('Enabling corepack');
            await execAsync('corepack enable');
            // Install dependencies
            logger.info('Installing dependencies');
            await execAsync('yarn install');
            // Setup Prisma
            logger.info('Setting up Prisma');
            await execAsync('yarn prisma generate');
            // Create necessary directories
            logger.info('Creating necessary directories');
            await execAsync('mkdir -p logs backups');
            // Setup PM2
            logger.info('Setting up PM2');
            await execAsync('pm2 install pm2-logrotate');
            await execAsync('pm2 set pm2-logrotate:max_size 10M');
            await execAsync('pm2 set pm2-logrotate:retain 7');
            logger.info('Development environment setup completed successfully');
            return { success: true };
        }
        catch (error) {
            logger.error('Setup failed', { error: error instanceof Error ? error.message : String(error) });
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
export default SetupTask;
