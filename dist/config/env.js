"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
var fs = require("fs");
var path = require("path");
var dotenv = require("dotenv");
var EnvLoader = /** @class */ (function () {
    function EnvLoader() {
        this.env = process.env.NODE_ENV || 'development';
        this.loadedVars = new Set();
    }
    EnvLoader.prototype.load = function () {
        // Load shared environment variables first
        this.loadFile('.env.shared');
        // Load environment-specific variables
        this.loadFile(".env.".concat(this.env));
        // Load local overrides last
        if (fs.existsSync('.env.local')) {
            this.loadFile('.env.local');
        }
        this.validateRequired();
    };
    EnvLoader.prototype.loadFile = function (filename) {
        var _this = this;
        var filePath = path.resolve(process.cwd(), filename);
        console.debug("Attempting to load ".concat(filename, " from ").concat(filePath));
        if (fs.existsSync(filePath)) {
            console.debug("Found ".concat(filename));
            var envConfig = dotenv.parse(fs.readFileSync(filePath));
            Object.entries(envConfig).forEach(function (_a) {
                var key = _a[0], value = _a[1];
                // Only consider a variable as loaded if it has a non-empty value
                if (!_this.loadedVars.has(key) || !process.env[key]) {
                    process.env[key] = value;
                    if (value) {
                        // Only mark as loaded if the value is non-empty
                        _this.loadedVars.add(key);
                        console.debug("Loaded ".concat(key, " = ").concat(value.substring(0, 3), "..."));
                    }
                }
                else {
                    console.debug("Skipped ".concat(key, " (already loaded with non-empty value)"));
                }
            });
        }
        else {
            console.debug("File ".concat(filename, " not found"));
        }
    };
    EnvLoader.prototype.validateRequired = function () {
        var required = [
            'DATABASE_URL',
            'AWS_REGION',
            'AWS_ACCESS_KEY_ID',
            'AWS_SECRET_ACCESS_KEY',
            'S3_BUCKET',
            'S3_PUT_AWS_ACCESS_KEY_ID',
            'S3_PUT_AWS_SECRET_ACCESS_KEY',
            'S3_BACKUP_PATH',
            'EMAIL_TO',
            'AUTH0_CLIENT_ID',
            'AUTH0_SECRET',
            'AUTH0_DOMAIN',
            'NEXTAUTH_SECRET',
            'SECRET',
            'MONITOR_EMAIL',
            'APP_PATH',
            'BACKUP_PATH',
            'LOG_PATH',
            'DB_PATH',
        ];
        var missing = required.filter(function (key) { return !process.env[key]; });
        if (missing.length > 0) {
            throw new Error("Missing required environment variables: ".concat(missing.join(', ')));
        }
    };
    return EnvLoader;
}());
exports.default = new EnvLoader();
