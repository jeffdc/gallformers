import { database } from '../../../../database';

export default async function getSourceById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const source = await db.get('SELECT * from source WHERE id = ?', [
        req.query.id
    ]);
    res.json(source);
}