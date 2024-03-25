import { NextApiRequest, NextApiResponse } from 'next';
import { apiIdEndpoint } from '../../../libs/api/apipage';
import { deleteGlossaryEntry } from '../../../libs/db/glossary.ts';

// GET: ../glossary/[id]
// fetches the glossary entry  id
//
export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    return await apiIdEndpoint(req, res, deleteGlossaryEntry);
};
