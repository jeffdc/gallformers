import { NextApiRequest, NextApiResponse } from 'next';
import { updateGallHosts } from '../../../libs/db/gallhost.js';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, updateGallHosts, onCompleteSendJson);
