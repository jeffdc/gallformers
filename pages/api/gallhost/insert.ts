import { NextApiRequest, NextApiResponse } from 'next';
import { updateGallHosts } from '../../../libs/db/gallhost';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, updateGallHosts, onCompleteSendJson);
