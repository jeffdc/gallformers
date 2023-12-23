import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../../libs/api/apipage.js';
import { moveGenera } from '../../../../libs/db/taxonomy.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    if (req.method !== 'POST') {
        res.status(405).end();
    } else {
        await apiUpsertEndpoint(req, res, moveGenera, onCompleteSendJson);
    }
};
