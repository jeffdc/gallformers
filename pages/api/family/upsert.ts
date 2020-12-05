import { NextApiRequest, NextApiResponse } from 'next';
import { upsertFamily } from '../../../libs/db/family';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertFamily, onCompleteRedirect('/family/'));
