import { NextApiRequest, NextApiResponse } from 'next';
import { upsertGall } from '../../../libs/db/gall';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertGall, onCompleteRedirect('gall/'));
