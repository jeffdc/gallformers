import { DB } from '../../../../database';

export default async function getHostsByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql = `SELECT hostsp.name, hostsp.synonyms, hostsp.commonnames
            FROM host 
            INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
            INNER JOIN species ON (host.species_id = species.species_id)
            WHERE host.species_id = ?`
    const hosts = DB.prepare(sql).all(req.query.id);
    res.json(hosts);
}