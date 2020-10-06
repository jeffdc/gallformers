import { DB } from '../../../../database';

export default async function getGallById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const gall = DB.prepare('SELECT * from gall WHERE id = ?').get(req.query.id);
    res.json(gall);
}