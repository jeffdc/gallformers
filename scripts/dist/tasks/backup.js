"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
const client_s3_1 = require("@aws-sdk/client-s3");
const aws_1 = __importDefault(require("../config/aws"));
const database_1 = __importDefault(require("../utils/database"));
const logger_1 = __importDefault(require("../utils/logger"));
const env_1 = __importDefault(require("../config/env"));
class BackupTask {
    constructor() {
        this.backupDir = path_1.default.join(process.cwd(), 'backups');
    }
    async execute() {
        try {
            // Load environment variables
            env_1.default.load();
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const backupPath = path_1.default.join(this.backupDir, `backup-${timestamp}.sqlite`);
            // Create local backup
            logger_1.default.info('Creating local backup', { backupPath });
            await database_1.default.backup(backupPath);
            // Upload to S3
            logger_1.default.info('Uploading backup to S3');
            const s3Client = aws_1.default.getS3Client();
            const bucket = aws_1.default.getBackupBucket();
            const s3Key = `backups/${timestamp}/database.sqlite`;
            await s3Client.send(new client_s3_1.PutObjectCommand({
                Bucket: bucket,
                Key: s3Key,
                Body: fs_1.default.createReadStream(backupPath),
            }));
            // Clean up local backup
            fs_1.default.unlinkSync(backupPath);
            logger_1.default.info('Backup completed successfully', {
                s3Bucket: bucket,
                s3Key,
            });
            return { success: true, s3Key };
        }
        catch (error) {
            logger_1.default.error('Backup failed', { error: error instanceof Error ? error.message : String(error) });
            throw error;
        }
    }
}
// If running directly (not imported as a module)
if (require.main === module) {
    new BackupTask().execute().catch((error) => {
        console.error('Backup failed:', error);
        process.exit(1);
    });
}
exports.default = BackupTask;
