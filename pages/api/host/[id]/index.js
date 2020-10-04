import { database } from '../../../../database';

export default async function getHostById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const host = await db.get('SELECT * from host WHERE id = ?', [
        req.query.id
    ]);
    res.json(host);
}