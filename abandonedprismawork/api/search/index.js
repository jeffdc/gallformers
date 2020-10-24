import { search } from '../../../database';

export default async function searchHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    const galls = await search(req.query);
  
    res.json(galls);
}