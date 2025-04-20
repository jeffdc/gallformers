"use strict";
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
Object.defineProperty(exports, "__esModule", { value: true });
var fs = require("fs");
var path = require("path");
var Logger = /** @class */ (function () {
    function Logger() {
        this.logDir = path.join(process.cwd(), 'logs');
        this.ensureLogDirectory();
    }
    Logger.prototype.ensureLogDirectory = function () {
        if (!fs.existsSync(this.logDir)) {
            fs.mkdirSync(this.logDir, { recursive: true });
        }
    };
    Logger.prototype.log = function (level, message, data) {
        if (data === void 0) { data = {}; }
        var timestamp = new Date().toISOString();
        var logEntry = __assign({ timestamp: timestamp, level: level, message: message }, data);
        // Console output
        console.log(JSON.stringify(logEntry));
        // File output
        var logFile = path.join(this.logDir, "".concat(level, ".log"));
        fs.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');
    };
    Logger.prototype.info = function (message, data) {
        if (data === void 0) { data = {}; }
        this.log('INFO', message, data);
    };
    Logger.prototype.error = function (message, data) {
        if (data === void 0) { data = {}; }
        this.log('ERROR', message, data);
    };
    Logger.prototype.warn = function (message, data) {
        if (data === void 0) { data = {}; }
        this.log('WARN', message, data);
    };
    return Logger;
}());
exports.default = new Logger();
