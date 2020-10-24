import { getGallFamilies } from '../../../database';

export default async function getGallFamiliesHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    
    res.json(await getGallFamilies());
}