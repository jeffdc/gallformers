import { NextApiRequest, NextApiResponse } from 'next';
import { apiIdEndpoint } from '../../../libs/api/apipage';
import { deletePlace } from '../../../libs/db/place';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deletePlace);
