import { NextApiRequest, NextApiResponse } from 'next';
import { upsertGlossary } from '../../../libs/db/glossary';
import { apiUpsertEndpoint, onCompleteRedirect } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiUpsertEndpoint(req, res, upsertGlossary, onCompleteRedirect('glossary#'));
