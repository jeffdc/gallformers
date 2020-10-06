import { DB } from '../../../../database';

export default async function getSourceById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const source = DB.prepare('SELECT * from source WHERE id = ?').all(req.query.id);
    res.json(source);
}