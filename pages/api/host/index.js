import { database } from '../../../database';

export default async function getHosts(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const hosts = await db.all('SELECT * from host ORDER BY name', [
        req.query.id
    ]);
    res.json(hosts);
}