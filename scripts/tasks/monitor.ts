import { exec } from 'child_process';
import { promisify } from 'util';
import logger from '../utils/logger';

const execAsync = promisify(exec);

async function monitorBackups() {
  try {
    logger.info('Starting backup monitoring...');
    const { stdout, stderr } = await execAsync('yarn backup --verify');
    if (stderr) {
      logger.error(`Backup verification error: ${stderr}`);
    } else {
      logger.info(`Backup verification success: ${stdout}`);
    }
  } catch (error: any) {
    logger.error(`Monitoring failed: ${error.message}`);
  }
}

monitorBackups().catch(error => logger.error(`Unhandled error: ${error.message}`));
