"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const env_1 = __importDefault(require("../config/env"));
// Load environment variables
env_1.default.load();
// Log some environment variables to verify they're loaded correctly
console.log('Environment:', process.env.NODE_ENV);
console.log('Database URL:', process.env.DATABASE_URL);
console.log('AWS Region:', process.env.AWS_REGION);
console.log('Auth0 Base URL:', process.env.AUTH0_BASE_URL);
// Test that required variables are present
try {
    env_1.default.load();
    console.log('✅ Environment validation passed');
}
catch (error) {
    console.error('❌ Environment validation failed:', error);
}
