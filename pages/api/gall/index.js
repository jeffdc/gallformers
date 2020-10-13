import { DB } from '../../../database';

export default async function getGalls(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT gall.detachable, gall.texture, gall.alignment, gall.walls, gl.loc, species.*
        FROM gall
        INNER JOIN galllocation AS gl ON (gl.loc_id = gall.loc_id)
        INNER JOIN species ON (species.species_id = gall.species_id)
        ORDER BY name ASC`;
    const galls = DB.prepare(sql).all();
    res.json(galls);
}