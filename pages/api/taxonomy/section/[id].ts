import { NextApiRequest, NextApiResponse } from 'next';
import { deleteTaxonomyEntry, getAllSpeciesForSectionOrGenus } from '../../../../libs/db/taxonomy';
import { apiIdEndpoint } from '../../../../libs/api/apipage';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> =>
    apiIdEndpoint(req, res, deleteTaxonomyEntry, getAllSpeciesForSectionOrGenus);
