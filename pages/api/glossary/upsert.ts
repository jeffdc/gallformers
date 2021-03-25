import { NextApiRequest, NextApiResponse } from 'next';
import { apiUpsertEndpoint, onCompleteSendJson } from '../../../libs/api/apipage';
import { upsertGlossary } from '../../../libs/db/glossary';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertGlossary, onCompleteSendJson);
