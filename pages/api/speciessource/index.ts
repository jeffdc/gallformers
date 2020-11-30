import { NextApiRequest, NextApiResponse } from 'next';
import { DeleteResults } from '../../../libs/apitypes';
import { deleteSpeciesSourceByIds, speciesSourceByIds } from '../../../libs/db/speciessource';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.speciesid || !req.query.sourceid) {
            res.status(400).end('No valid query provided. You must provide both a speciesid and a sourceid.');
        }
        const speciesid = req.query.speciesid as string;
        const sourceid = req.query.sourceid as string;

        if (req.method === 'GET') {
            res.status(200).json(await speciesSourceByIds(speciesid, sourceid));
        } else if (req.method === 'DELETE') {
            const results = await deleteSpeciesSourceByIds(speciesid, sourceid);
            const deleteResults = {
                name: `mapping between speciesid: ${results?.species_id} and sourceid: ${results?.source_id}`,
            } as DeleteResults;
            res.status(200).json(deleteResults);
        }
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: e.message });
    }
};
