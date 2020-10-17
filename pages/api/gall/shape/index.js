import { DB } from '../../../../database';

export default async function getShapes(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const data = DB.prepare('SELECT * from shape ORDER BY shape ASC').all();
    res.json(data);
}