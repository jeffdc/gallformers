import { DB } from '../../../database';

function allIfNull(x) {
    !x ? '%' : x
}

export default async function search(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let q = req.query;

    let sql = 
        `SELECT * from gall 
        INNER JOIN gallhost ON (gallhost.gallid = gall.id)
        INNER JOIN host ON (gallhost.hostid = host.id)
        INNER JOIN galllocation ON (galllocation.id = galllocid) 
        WHERE detachable = ? AND 
            texture LIKE ? AND 
            alignment LIKE ? AND 
            walls LIKE ? AND 
            host.name LIKE ? AND 
            galllocation.loc LIKE ? 
        ORDER BY name ASC`;
    var stmt = DB.prepare(sql);
    const galls = stmt.all(q.detachable ? 1 : 0, allIfNull(q.texture), allIfNull(q.alignment), allIfNull(q.walls), 
             allIfNull(q.host), allIfNull(q.location));
    
    res.json(galls);
}

/*

SELECT * from gall 
        INNER JOIN gallhost ON (gallhost.gallid = gall.id)
        INNER JOIN host ON (gallhost.hostid = host.id)
        INNER JOIN galllocation ON (galllocation.id = galllocid) 
        WHERE detachable = 1 AND 
            texture LIKE '%' AND 
            alignment LIKE '%' AND 
            walls LIKE '%' AND 
            host.name LIKE 'Quercus alba' AND 
            galllocation.loc LIKE '%'
        ORDER BY name ASC; 

 */