import db from './db';

export type Entry = {
    id: number;
    word: string;
    definition: string;
    urls: string[];
};

export const allGlossaryEntries = async (): Promise<Entry[]> => {
    return db.glossary
        .findMany({
            orderBy: { word: 'asc' },
        })
        .then((gs) => {
            return gs.map((g) => {
                return {
                    ...g,
                    urls: g.urls.split('\t'),
                };
            });
        });
};
