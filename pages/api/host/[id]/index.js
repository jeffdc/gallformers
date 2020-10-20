import { getHost } from '../../../../database';

export default async function getHostHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }
    
    res.json(await getHost(req.query.id));
}