import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';
import { upsertSource } from '../../../libs/db/source';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertSource, onCompleteSendJson);
