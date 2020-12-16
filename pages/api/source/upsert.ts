import { NextApiRequest, NextApiResponse } from 'next';
import { upsertSource } from '../../../libs/db/source';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertSource, onCompleteRedirect('source/'));
