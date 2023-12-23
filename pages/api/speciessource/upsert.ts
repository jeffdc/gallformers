import { NextApiRequest, NextApiResponse } from 'next';
import { upsertSpeciesSource } from '../../../libs/db/speciessource.js';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertSpeciesSource, onCompleteSendJson);
