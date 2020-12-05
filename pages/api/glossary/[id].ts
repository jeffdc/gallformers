import { NextApiRequest, NextApiResponse } from 'next';
import { deleteGlossaryEntry } from '../../../libs/db/glossary';
import { apiIdEndpoint } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteGlossaryEntry);
