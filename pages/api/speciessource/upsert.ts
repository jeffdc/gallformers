import { NextApiRequest, NextApiResponse } from 'next';
import { upsertSpeciesSource } from '../../../libs/db/speciessource';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertSpeciesSource, onCompleteSendJson);
