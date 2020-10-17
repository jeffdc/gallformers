import { DB } from '../../../../database';

export default async function getCells(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const data = DB.prepare('SELECT * from cells ORDER BY cells ASC').all();
    res.json(data);
}