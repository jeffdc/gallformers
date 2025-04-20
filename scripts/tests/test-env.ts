import envLoader from '../config/env';

// Load environment variables
envLoader.load();

// Log some environment variables to verify they're loaded correctly
console.log('Environment:', process.env.NODE_ENV);
console.log('Database URL:', process.env.DATABASE_URL);
console.log('AWS Region:', process.env.AWS_REGION);
console.log('Auth0 Base URL:', process.env.AUTH0_BASE_URL);

// Test that required variables are present
try {
    envLoader.load();
    console.log('✅ Environment validation passed');
} catch (error) {
    console.error('❌ Environment validation failed:', error);
}
