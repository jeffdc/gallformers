import { DB } from '../../../../database';

export default async function getHostsByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const hosts = DB.prepare('SELECT * from gallhost INNER JOIN host ON gallhost.hostid = host.id WHERE id = ?').all(req.query.id);
    res.json(hosts);
}