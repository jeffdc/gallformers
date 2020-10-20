import { getAlignments } from '../../../../database';

export default async function getAlignmentsHTTP(req, res) {
    if (req.method !== 'GET') {
        res.status(405).json({message: "Only GET is supported."});
    }

    res.json(await getAlignments());
}