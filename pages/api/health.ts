import { NextApiRequest, NextApiResponse } from 'next';
import db from '../../libs/db/db';

interface HealthStatus {
    status: 'healthy' | 'unhealthy';
    timestamp: string;
    checks: {
        database: boolean;
        server: boolean;
    };
    version?: string;
}

export default async function handler(req: NextApiRequest, res: NextApiResponse<HealthStatus>): Promise<void> {
    let databaseHealthy = false;

    try {
        // Test database connectivity using the same db instance as the app
        await db.$queryRaw`SELECT 1`;
        databaseHealthy = true;
    } catch (error) {
        console.error('Health check - Database connection failed:', error);
        databaseHealthy = false;
    }

    const serverHealthy = true; // If we got here, server is responding
    const overallHealthy = databaseHealthy && serverHealthy;

    const healthStatus: HealthStatus = {
        status: overallHealthy ? 'healthy' : 'unhealthy',
        timestamp: new Date().toISOString(),
        checks: {
            database: databaseHealthy,
            server: serverHealthy,
        },
        version: process.env.npm_package_version || 'unknown',
    };

    // Return appropriate HTTP status code
    const statusCode = overallHealthy ? 200 : 503;
    res.status(statusCode).json(healthStatus);
}
