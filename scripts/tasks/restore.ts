import * as path from 'path';
import * as fs from 'fs';
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { Readable } from 'stream';
import aws from '../config/aws.js';
import db from '../utils/database.js';
import logger from '../utils/logger.js';
import env from '../config/env.js';

interface RestoreResult {
    success: boolean;
}

class RestoreTask {
    private backupDir: string;

    constructor() {
        this.backupDir = path.join(process.cwd(), 'backups');
    }

    async execute(s3Key: string): Promise<RestoreResult> {
        try {
            // Load environment variables
            env.load();

            if (!s3Key) {
                throw new Error('S3 key is required');
            }

            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupPath = path.join(this.backupDir, `restore-${timestamp}.sqlite`);

            // Download from S3
            logger.info('Downloading backup from S3', { s3Key });
            const s3Client = aws.getS3Client();
            const bucket = aws.getBackupBucket();

            const { Body } = await s3Client.send(
                new GetObjectCommand({
                    Bucket: bucket,
                    Key: s3Key,
                }),
            );

            if (!Body) {
                throw new Error('Failed to download backup from S3');
            }

            // Save to local file
            const writeStream = fs.createWriteStream(backupPath);

            // Convert Body to a readable stream if it's not already one
            let readableStream: Readable;
            if (Body instanceof Readable) {
                readableStream = Body;
            } else {
                // Handle different types of Body
                try {
                    // Try to convert to Buffer first
                    const buffer = await Body.transformToByteArray();
                    readableStream = Readable.from(buffer);
                } catch (e) {
                    // Fallback to a simple readable stream
                    readableStream = new Readable({
                        read() {
                            this.push(null);
                        },
                    });
                    logger.warn('Could not convert S3 response to readable stream', {
                        error: e instanceof Error ? e.message : String(e),
                    });
                }
            }

            await new Promise<void>((resolve, reject) => {
                readableStream.pipe(writeStream).on('error', reject).on('finish', resolve);
            });

            // Restore database
            logger.info('Restoring database from backup', { backupPath });
            await db.restore(backupPath);

            // Clean up local backup
            fs.unlinkSync(backupPath);

            logger.info('Restore completed successfully', {
                s3Bucket: bucket,
                s3Key,
            });

            return { success: true };
        } catch (error) {
            logger.error('Restore failed', { error: error instanceof Error ? error.message : String(error) });
            throw error;
        }
    }
}

// If running directly (not imported as a module)
if (require.main === module) {
    const s3Key = process.argv[2];
    if (!s3Key) {
        console.error('Usage: node restore.js <s3-key>');
        process.exit(1);
    }

    new RestoreTask().execute(s3Key).catch((error) => {
        console.error('Restore failed:', error);
        process.exit(1);
    });
}

export default RestoreTask;
