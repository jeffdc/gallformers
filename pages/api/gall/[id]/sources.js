import { database } from '../../../../database';

export default async function getSourcesByGallId(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    let db = await database();
    const hosts = await db.get('SELECT * from gallsource INNER JOIN source ON gallsource.sourceid = source.id WHERE id = ?', [
        req.query.id
    ]);
    res.json(hosts);
}