import { delBasePath } from 'next/dist/next-server/lib/router/router';
import { DB } from '../../../database';

export default async function getHosts(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const hosts = DB.prepare('SELECT * from host ORDER BY name').all();
    res.json(hosts);
}