import { database } from '../../../../database';

export default async function getGallById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const gall = await db.get('SELECT * from gall WHERE id = ?', [
        req.query.id
    ]);
    res.json(gall);
}