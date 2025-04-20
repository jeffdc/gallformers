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
var fs = require("fs");
var path = require("path");
var child_process_1 = require("child_process");
var util_1 = require("util");
var execAsync = (0, util_1.promisify)(child_process_1.exec);
var Database = /** @class */ (function () {
    function Database() {
        this.dbPath = path.join(process.cwd(), 'gallformers.sqlite');
    }
    Database.prototype.backup = function (backupPath) {
        return __awaiter(this, void 0, void 0, function () {
            var backupDir;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        if (!fs.existsSync(this.dbPath)) {
                            throw new Error('Database file not found');
                        }
                        backupDir = path.dirname(backupPath);
                        if (!fs.existsSync(backupDir)) {
                            fs.mkdirSync(backupDir, { recursive: true });
                        }
                        // Copy database file
                        fs.copyFileSync(this.dbPath, backupPath);
                        // Verify backup
                        return [4 /*yield*/, this.verifyBackup(backupPath)];
                    case 1:
                        // Verify backup
                        _a.sent();
                        return [2 /*return*/, backupPath];
                }
            });
        });
    };
    Database.prototype.restore = function (backupPath) {
        return __awaiter(this, void 0, void 0, function () {
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        if (!fs.existsSync(backupPath)) {
                            throw new Error('Backup file not found');
                        }
                        // Verify backup before restoring
                        return [4 /*yield*/, this.verifyBackup(backupPath)];
                    case 1:
                        // Verify backup before restoring
                        _a.sent();
                        // Stop any running processes that might be using the database
                        return [4 /*yield*/, this.stopProcesses()];
                    case 2:
                        // Stop any running processes that might be using the database
                        _a.sent();
                        // Restore database
                        fs.copyFileSync(backupPath, this.dbPath);
                        // Verify restored database
                        return [4 /*yield*/, this.verifyBackup(this.dbPath)];
                    case 3:
                        // Verify restored database
                        _a.sent();
                        return [2 /*return*/];
                }
            });
        });
    };
    Database.prototype.verifyBackup = function (dbPath) {
        return __awaiter(this, void 0, void 0, function () {
            var stdout, error_1;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        _a.trys.push([0, 2, , 3]);
                        return [4 /*yield*/, execAsync("sqlite3 \"".concat(dbPath, "\" \"PRAGMA integrity_check;\""))];
                    case 1:
                        stdout = (_a.sent()).stdout;
                        if (stdout.trim() !== 'ok') {
                            throw new Error("Database integrity check failed: ".concat(stdout));
                        }
                        return [3 /*break*/, 3];
                    case 2:
                        error_1 = _a.sent();
                        if (error_1 instanceof Error) {
                            throw new Error("Failed to verify database: ".concat(error_1.message));
                        }
                        else {
                            throw new Error('Failed to verify database: Unknown error');
                        }
                        return [3 /*break*/, 3];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    Database.prototype.stopProcesses = function () {
        return __awaiter(this, void 0, void 0, function () {
            var _a;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        _b.trys.push([0, 2, , 3]);
                        // Stop PM2 processes if running
                        return [4 /*yield*/, execAsync('pm2 stop all || true')];
                    case 1:
                        // Stop PM2 processes if running
                        _b.sent();
                        return [3 /*break*/, 3];
                    case 2:
                        _a = _b.sent();
                        return [3 /*break*/, 3];
                    case 3: return [2 /*return*/];
                }
            });
        });
    };
    return Database;
}());
exports.default = new Database();
