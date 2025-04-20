import * as path from 'path';
import * as fs from 'fs';
import { PutObjectCommand } from '@aws-sdk/client-s3';
import aws from '../config/aws.js';
import db from '../utils/database.js';
import logger from '../utils/logger.js';
import env from '../config/env.js';
import { fileURLToPath } from 'url';
class BackupTask {
    backupDir;
    constructor() {
        this.backupDir = path.join(process.cwd(), 'backups');
    }
    async execute() {
        try {
            // Load environment variables
            env.load();
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupPath = path.join(this.backupDir, `backup-${timestamp}.sqlite`);
            // Create local backup
            logger.info('Creating local backup', { backupPath });
            await db.backup(backupPath);
            // Upload to S3
            logger.info('Uploading backup to S3');
            const s3Client = aws.getS3Client();
            const bucket = aws.getBackupBucket();
            const s3Key = `backups/${timestamp}/database.sqlite`;
            await s3Client.send(new PutObjectCommand({
                Bucket: bucket,
                Key: s3Key,
                Body: fs.createReadStream(backupPath),
            }));
            // Clean up local backup
            fs.unlinkSync(backupPath);
            logger.info('Backup completed successfully', {
                s3Bucket: bucket,
                s3Key,
            });
            return { success: true, s3Key };
        }
        catch (error) {
            logger.error('Backup failed', { error: error instanceof Error ? error.message : String(error) });
            throw error;
        }
    }
}
// If running directly (not imported as a module)
if (import.meta.url === fileURLToPath(process.argv[1])) {
    new BackupTask().execute().catch((error) => {
        console.error('Backup failed:', error);
        process.exit(1);
    });
}
export default BackupTask;
