import { DB } from '../../../../database';

export default async function getSourcesByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const hosts = DB.prepare(
        'SELECT * from gallsource INNER JOIN source ON gallsource.sourceid = source.id WHERE id = ?').all(req.query.id);
    res.json(hosts);
}