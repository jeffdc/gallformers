import { database } from '../../../../database';

export default async function getHostsByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const hosts = await db.get('SELECT * from gallhost INNER JOIN host ON gallhost.hostid = host.id WHERE id = ?', [
        req.query.id
    ]);
    res.json(hosts);
}