import { DB } from '../../../../database';

export default async function getWalls(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const data = DB.prepare('SELECT * from walls ORDER BY walls ASC').all();
    res.json(data);
}