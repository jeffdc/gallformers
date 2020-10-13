import { delBasePath } from 'next/dist/next-server/lib/router/router';
import { DB } from '../../../database';

export default async function getHosts(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql =
        `SELECT DISTINCT hostsp.name, hostsp.synonyms, hostsp.commonnames
        FROM host 
        INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
        INNER JOIN species ON (host.species_id = species.species_id)
        ORDER BY hostsp.name`;
    const hosts = DB.prepare(sql).all();
    res.json(hosts);
}

/*
SELECT DISTINCT hostsp.name, hostsp.synonyms, hostsp.commonnames
        FROM host 
        INNER JOIN species as hostsp ON (host.host_species_id = hostsp.species_id) 
        INNER JOIN species ON (host.species_id = species.species_id)
        ORDER BY hostsp.name;
*/