import { DB } from '../../../../database';

export default async function getHostById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }
    const host = DB.prepare('SELECT * from host WHERE id = ?').all(req.query.id);
    res.json(host);
}