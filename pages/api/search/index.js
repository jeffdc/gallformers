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
        `SELECT DISTINCT v_gall.*, hostsp.name as host_name, hostsp.species_id AS host_species_id
        FROM v_gall
        INNER JOIN host ON (v_gall.species_id = host.species_id)
        INNER JOIN species AS hostsp ON (hostsp.species_id = host.host_species_id)
        WHERE (detachable = ? OR detachable is NOT NULL) AND 
            (texture LIKE ? OR texture IS NULL) AND 
            (alignment LIKE ? OR alignment IS NULL) AND 
            (walls LIKE ? OR walls IS NULL) AND 
            hostsp.name LIKE ? AND 
            (loc LIKE ? OR loc IS NULL)
        ORDER BY v_gall.name ASC`;
    var stmt = DB.prepare(sql);
    const galls = stmt.all(q.detachable ? 0 : 1, allIfNull(q.texture), allIfNull(q.alignment), allIfNull(q.walls), 
             allIfNull(q.host), allIfNull(q.location));

    res.json(galls);
}

/*
        SELECT DISTINCT v_gall.*, hostsp.name as host_name, hostsp.species_id AS host_species_id
        FROM v_gall
        INNER JOIN host ON (v_gall.species_id = host.species_id)
        INNER JOIN species AS hostsp ON (hostsp.species_id = host.host_species_id)
        WHERE (detachable = 0 OR detachable IS NOT NULL) AND 
            (texture LIKE '%' OR texture IS NULL) AND 
            (alignment LIKE '%' OR alignment IS NULL) AND 
            (walls LIKE '%' OR walls IS NULL) AND 
            hostsp.name LIKE 'Quercus velutina' AND 
            (loc LIKE '%' OR loc IS NULL)
        ORDER BY v_gall.name ASC;


 */