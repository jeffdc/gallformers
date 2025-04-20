import { S3Client } from '@aws-sdk/client-s3';
class AWSConfig {
    s3Client;
    constructor() {
        this.s3Client = new S3Client({
            region: process.env.AWS_REGION,
            credentials: {
                accessKeyId: process.env.AWS_ACCESS_KEY_ID || '',
                secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || '',
            },
        });
    }
    getS3Client() {
        return this.s3Client;
    }
    getBackupBucket() {
        return process.env.S3_BUCKET || '';
    }
}
export default new AWSConfig();
