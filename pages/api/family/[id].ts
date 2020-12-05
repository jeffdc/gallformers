import { NextApiRequest, NextApiResponse } from 'next';
import { deleteFamily } from '../../../libs/db/family';
import { apiIdEndpoint } from '../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteFamily);
