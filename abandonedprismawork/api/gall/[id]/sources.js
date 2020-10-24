import { getSourcesByGall } from '../../../../database';

export default async function getSourcesByGallHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getSourcesByGall(req.query.id));
}