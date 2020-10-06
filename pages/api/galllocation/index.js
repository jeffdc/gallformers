import { DB } from '../../../database';

export default async function getGallLocations(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const locs = DB.prepare('SELECT * from galllocation ORDER BY loc ASC').all();
    res.json(locs);
}