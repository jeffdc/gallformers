import { NextApiRequest, NextApiResponse } from 'next';
import { upsertTaxonomy } from '../../../libs/db/taxonomy';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertTaxonomy, onCompleteRedirect('family/'));
