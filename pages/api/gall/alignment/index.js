import { DB } from '../../../../database';

export default async function getAlignments(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const data = DB.prepare('SELECT * from alignment ORDER BY alignment ASC').all();
    res.json(data);
}