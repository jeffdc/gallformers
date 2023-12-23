import { NextApiRequest, NextApiResponse } from 'next';
import { deleteGlossaryEntry } from '../../../libs/db/glossary.js';
import { apiIdEndpoint } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteGlossaryEntry);
