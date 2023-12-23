import { NextApiRequest, NextApiResponse } from 'next';
import { upsertTaxonomy } from '../../../libs/db/taxonomy';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertTaxonomy, onCompleteSendJson);
