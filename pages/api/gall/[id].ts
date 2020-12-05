import { NextApiRequest, NextApiResponse } from 'next';
import { deleteGall } from '../../../libs/db/gall';
import { apiIdEndpoint } from '../../../libs/pages/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deleteGall);
