import { getHostsByGall } from '../../../../database';

export default async function getHostsByGallHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }
   
    res.json(await getHostsByGall(req.query.id));
}