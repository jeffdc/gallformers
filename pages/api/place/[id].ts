import { NextApiRequest, NextApiResponse } from 'next';
import { apiIdEndpoint } from '../../../libs/api/apipage.js';
import { deletePlace } from '../../../libs/db/place.js';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => apiIdEndpoint(req, res, deletePlace);
