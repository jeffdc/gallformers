import { DB } from '../../../../database';

export default async function getGallById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let sql = 
        `SELECT *
        FROM v_gall
        WHERE species_id = ?`;
    const gall = DB.prepare(sql).get(req.query.id);
    res.json(gall);
}