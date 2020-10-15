import { DB } from '../../../../database';

export default async function getHostById(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql = 
        `SELECT DISTINCT species.* 
        FROM host 
        INNER JOIN species ON (species.species_id = host.host_species_id)
        WHERE species.species_id = ?`;
    const host = DB.prepare(sql).get(req.query.id);
    res.json(host);
}