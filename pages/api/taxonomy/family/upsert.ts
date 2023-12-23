import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../../libs/api/apipage.js';
import { upsertFamily } from '../../../../libs/db/taxonomy.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertFamily, onCompleteSendJson);
