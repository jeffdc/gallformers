import { NextApiRequest, NextApiResponse } from 'next';
import { deleteGall } from '../../../libs/db/gall.js';
import { apiIdEndpoint } from '../../../libs/api/apipage.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteGall);
