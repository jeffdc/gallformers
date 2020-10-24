import { getFamilies } from '../../../database';

export default async function getFamiliesHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getFamilies());
}

