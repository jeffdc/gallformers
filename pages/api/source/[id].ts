import { NextApiRequest, NextApiResponse } from 'next';
import { deleteSource } from '../../../libs/db/source';
import { apiIdEndpoint } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteSource);
