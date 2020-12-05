import { NextApiRequest, NextApiResponse } from 'next';
import { insertGallHosts } from '../../../libs/db/gallhost';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, insertGallHosts, onCompleteSendJson);
