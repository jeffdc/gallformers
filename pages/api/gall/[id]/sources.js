import { DB } from '../../../../database';

export default async function getSourcesByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const sql = `
        SELECT DISTINCT * 
        FROM speciessource 
        INNER JOIN source ON (speciessource.source_id = source.source_id)
        WHERE species_id = ?`
    const hosts = DB.prepare(sql).all(req.query.id);
    res.json(hosts);
}