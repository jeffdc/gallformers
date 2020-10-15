import { DB } from '../../../../database';

export default async function getGallsByHostId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql = `SELECT DISTINCT species.species_id, species.name, species.synonyms, species.commonnames
            FROM host 
            INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
            INNER JOIN species ON (host.species_id = species.species_id)
            WHERE host.host_species_id = ?`
    const galls = DB.prepare(sql).all(req.query.id);
    res.json(galls);
}