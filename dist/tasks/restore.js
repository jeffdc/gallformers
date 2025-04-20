"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var path = require("path");
var fs = require("fs");
var client_s3_1 = require("@aws-sdk/client-s3");
var stream_1 = require("stream");
var aws_1 = require("../config/aws");
var database_1 = require("../utils/database");
var logger_1 = require("../utils/logger");
var env_1 = require("../config/env");
var RestoreTask = /** @class */ (function () {
    function RestoreTask() {
        this.backupDir = path.join(process.cwd(), 'backups');
    }
    RestoreTask.prototype.execute = function (s3Key) {
        return __awaiter(this, void 0, void 0, function () {
            var timestamp, backupPath, s3Client, bucket, Body, writeStream_1, readableStream_1, buffer, e_1, error_1;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 8, , 9]);
                        // Load environment variables
                        env_1.default.load();
                        if (!s3Key) {
                            throw new Error('S3 key is required');
                        }
                        timestamp = new Date().toISOString().replace(/[:.]/g, '-');
                        backupPath = path.join(this.backupDir, "restore-".concat(timestamp, ".sqlite"));
                        // Download from S3
                        logger_1.default.info('Downloading backup from S3', { s3Key: s3Key });
                        s3Client = aws_1.default.getS3Client();
                        bucket = aws_1.default.getBackupBucket();
                        return [4 /*yield*/, s3Client.send(new client_s3_1.GetObjectCommand({
                                Bucket: bucket,
                                Key: s3Key,
                            }))];
                    case 1:
                        Body = (_a.sent()).Body;
                        if (!Body) {
                            throw new Error('Failed to download backup from S3');
                        }
                        writeStream_1 = fs.createWriteStream(backupPath);
                        if (!(Body instanceof stream_1.Readable)) return [3 /*break*/, 2];
                        readableStream_1 = Body;
                        return [3 /*break*/, 5];
                    case 2:
                        _a.trys.push([2, 4, , 5]);
                        return [4 /*yield*/, Body.transformToByteArray()];
                    case 3:
                        buffer = _a.sent();
                        readableStream_1 = stream_1.Readable.from(buffer);
                        return [3 /*break*/, 5];
                    case 4:
                        e_1 = _a.sent();
                        // Fallback to a simple readable stream
                        readableStream_1 = new stream_1.Readable({
                            read: function () {
                                this.push(null);
                            },
                        });
                        logger_1.default.warn('Could not convert S3 response to readable stream', {
                            error: e_1 instanceof Error ? e_1.message : String(e_1),
                        });
                        return [3 /*break*/, 5];
                    case 5: return [4 /*yield*/, new Promise(function (resolve, reject) {
                            readableStream_1.pipe(writeStream_1).on('error', reject).on('finish', resolve);
                        })];
                    case 6:
                        _a.sent();
                        // Restore database
                        logger_1.default.info('Restoring database from backup', { backupPath: backupPath });
                        return [4 /*yield*/, database_1.default.restore(backupPath)];
                    case 7:
                        _a.sent();
                        // Clean up local backup
                        fs.unlinkSync(backupPath);
                        logger_1.default.info('Restore completed successfully', {
                            s3Bucket: bucket,
                            s3Key: s3Key,
                        });
                        return [2 /*return*/, { success: true }];
                    case 8:
                        error_1 = _a.sent();
                        logger_1.default.error('Restore failed', { error: error_1 instanceof Error ? error_1.message : String(error_1) });
                        throw error_1;
                    case 9: return [2 /*return*/];
                }
            });
        });
    };
    return RestoreTask;
}());
// If running directly (not imported as a module)
if (require.main === module) {
    var s3Key = process.argv[2];
    if (!s3Key) {
        console.error('Usage: node restore.js <s3-key>');
        process.exit(1);
    }
    new RestoreTask().execute(s3Key).catch(function (error) {
        console.error('Restore failed:', error);
        process.exit(1);
    });
}
exports.default = RestoreTask;
