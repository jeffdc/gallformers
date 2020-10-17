import { DB } from '../../../database';

export default async function getGalls(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT v_gall.*
        FROM v_gall
        ORDER BY name ASC`;
    const galls = DB.prepare(sql).all();
    res.json(galls);
}