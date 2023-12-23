import { NextApiRequest, NextApiResponse } from 'next';
import { deleteSource } from '../../../libs/db/source.js';
import { apiIdEndpoint } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteSource);
