"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const client_s3_1 = require("@aws-sdk/client-s3");
const stream_1 = require("stream");
const aws_1 = __importDefault(require("../config/aws"));
const database_1 = __importDefault(require("../utils/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const env_1 = __importDefault(require("../config/env"));
class RestoreTask {
    constructor() {
        this.backupDir = path_1.default.join(process.cwd(), 'backups');
    }
    async execute(s3Key) {
        try {
            // Load environment variables
            env_1.default.load();
            if (!s3Key) {
                throw new Error('S3 key is required');
            }
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupPath = path_1.default.join(this.backupDir, `restore-${timestamp}.sqlite`);
            // Download from S3
            logger_1.default.info('Downloading backup from S3', { s3Key });
            const s3Client = aws_1.default.getS3Client();
            const bucket = aws_1.default.getBackupBucket();
            const { Body } = await s3Client.send(new client_s3_1.GetObjectCommand({
                Bucket: bucket,
                Key: s3Key,
            }));
            if (!Body) {
                throw new Error('Failed to download backup from S3');
            }
            // Save to local file
            const writeStream = fs_1.default.createWriteStream(backupPath);
            // Convert Body to a readable stream if it's not already one
            let readableStream;
            if (Body instanceof stream_1.Readable) {
                readableStream = Body;
            }
            else {
                // Handle different types of Body
                try {
                    // Try to convert to Buffer first
                    const buffer = await Body.transformToByteArray();
                    readableStream = stream_1.Readable.from(buffer);
                }
                catch (e) {
                    // Fallback to a simple readable stream
                    readableStream = new stream_1.Readable({
                        read() {
                            this.push(null);
                        },
                    });
                    logger_1.default.warn('Could not convert S3 response to readable stream', {
                        error: e instanceof Error ? e.message : String(e),
                    });
                }
            }
            await new Promise((resolve, reject) => {
                readableStream.pipe(writeStream).on('error', reject).on('finish', resolve);
            });
            // Restore database
            logger_1.default.info('Restoring database from backup', { backupPath });
            await database_1.default.restore(backupPath);
            // Clean up local backup
            fs_1.default.unlinkSync(backupPath);
            logger_1.default.info('Restore completed successfully', {
                s3Bucket: bucket,
                s3Key,
            });
            return { success: true };
        }
        catch (error) {
            logger_1.default.error('Restore failed', { error: error instanceof Error ? error.message : String(error) });
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
exports.default = RestoreTask;
