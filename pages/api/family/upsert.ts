import { NextApiRequest, NextApiResponse } from 'next';
import { upsertFamily } from '../../../libs/db/taxonomy';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertFamily, onCompleteRedirect('family/'));
