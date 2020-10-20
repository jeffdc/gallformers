import { getGalls } from '../../../database';

export default async function getGallsHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getGalls());
}