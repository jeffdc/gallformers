import { NextApiRequest, NextApiResponse } from 'next';
import { deleteTaxonomyEntry } from '../../../../libs/db/taxonomy.js';
import { apiIdEndpoint } from '../../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteTaxonomyEntry);
