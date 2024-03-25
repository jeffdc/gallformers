import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';
import { upsertPlace } from '../../../libs/db/place.ts';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertPlace, onCompleteSendJson);
