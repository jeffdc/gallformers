import { DB } from '../../../database';

function allIfNull(x) {
    return !x ? '%' : x
}

export default async function search(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let q = req.query;

    let sql = 
        `SELECT DISTINCT species.*, 
                gall.detachable, gall.texture, gall.alignment, gall.walls,
                hostsp.name as hostname, host.host_species_id as hostid,
                galllocation.loc
        FROM gall 
        INNER JOIN host ON (host.species_id = gall.species_id)
        INNER JOIN species ON (gall.species_id = species.species_id)
        INNER JOIN species as hostsp ON (hostsp.species_id = host.host_species_id)
        INNER JOIN galllocation ON (galllocation.loc_id = gall.loc_id) 
        WHERE gall.detachable = ? AND 
            (gall.texture LIKE ? OR gall.texture IS NULL) AND 
            (gall.alignment LIKE ? OR gall.alignment IS NULL) AND 
            (gall.walls LIKE ? OR gall.walls IS NULL) AND 
            hostsp.name LIKE ? AND 
            (galllocation.loc LIKE ? OR galllocation.loc IS NULL)
        ORDER BY species.name ASC`;
    var stmt = DB.prepare(sql);
    const galls = stmt.all(q.detachable ? 0 : 1, allIfNull(q.texture), allIfNull(q.alignment), allIfNull(q.walls), 
             allIfNull(q.host), allIfNull(q.location));

    res.json(galls);
}

/*
        SELECT species.*, 
                gall.detachable, gall.texture, gall.alignment, gall.walls,
                hostsp.name as hostname, host.host_species_id as hostid,
                galllocation.loc
        FROM gall 
        INNER JOIN host ON (host.species_id = gall.species_id)
        INNER JOIN species ON (gall.species_id = species.species_id)
        INNER JOIN species as hostsp ON (hostsp.species_id = host.host_species_id)
        INNER JOIN galllocation ON (galllocation.loc_id = gall.loc_id) 
        WHERE gall.detachable = 0 AND 
            (gall.texture LIKE '%' OR gall.texture IS NULL) AND 
            (gall.alignment LIKE '%' OR gall.alignment IS NULL) AND 
            (gall.walls LIKE '%' OR gall.walls IS NULL) AND 
            hostsp.name LIKE 'Quercus alba' AND 
            (galllocation.loc LIKE '%' OR galllocation.loc IS NULL)
        ORDER BY species.name ASC;


 */