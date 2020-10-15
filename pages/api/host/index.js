import { DB } from '../../../database';

export default async function getHosts(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT DISTINCT species.*
        FROM host 
        INNER JOIN species ON (host.host_species_id = species.species_id)
        ORDER BY species.name ASC`;
    const hosts = DB.prepare(sql).all();
    res.json(hosts);
}