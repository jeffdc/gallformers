import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';
import { upsertTaxonomy } from '../../../libs/db/taxonomy';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertTaxonomy, onCompleteSendJson);
