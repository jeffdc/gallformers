import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';
import { upsertHost } from '../../../libs/db/host';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertHost, onCompleteSendJson);
