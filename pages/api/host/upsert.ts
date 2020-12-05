import { NextApiRequest, NextApiResponse } from 'next';
import { upsertHost } from '../../../libs/db/host';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertHost, onCompleteRedirect('/host/'));
