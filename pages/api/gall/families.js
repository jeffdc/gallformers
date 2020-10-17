import { DB } from '../../../database';

export default async function getFamilies(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT DISTINCT v_gall.family
        FROM v_gall
        ORDER BY family ASC`;
    const families = DB.prepare(sql).all();
    res.json(families);
}