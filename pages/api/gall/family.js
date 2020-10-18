import { DB } from '../../../database';

export default async function getFamilies(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT DISTINCT family.*
        FROM gall
            INNER JOIN
            species ON (gall.species_id = species.species_id) 
            INNER JOIN
            family ON (species.family_id = family.family_id)      
        ORDER BY family.name ASC`;
    const families = DB.prepare(sql).all();
    res.json(families);
}