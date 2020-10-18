import { DB } from '../../../database';

export default async function getFamilies(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT *
        FROM family
        ORDER BY name ASC`;
    const families = DB.prepare(sql).all();
    res.json(families);
}