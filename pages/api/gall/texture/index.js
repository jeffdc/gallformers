import { DB } from '../../../../database';

export default async function getTextures(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const data = DB.prepare('SELECT * from texture ORDER BY texture ASC').all();
    res.json(data);
}