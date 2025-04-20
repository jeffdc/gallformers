"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var client_s3_1 = require("@aws-sdk/client-s3");
var AWSConfig = /** @class */ (function () {
    function AWSConfig() {
        this.s3Client = new client_s3_1.S3Client({
            region: process.env.AWS_REGION,
            credentials: {
                accessKeyId: process.env.AWS_ACCESS_KEY_ID || '',
                secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || '',
            },
        });
    }
    AWSConfig.prototype.getS3Client = function () {
        return this.s3Client;
    };
    AWSConfig.prototype.getBackupBucket = function () {
        return process.env.S3_BUCKET || '';
    };
    return AWSConfig;
}());
exports.default = new AWSConfig();
