import { makeSchema, objectType, queryType } from 'nexus';
import { join } from 'path';
import { allGlossaryEntries, Entry } from '../libs/db/glossary';
import { mightFailWithArray } from '../libs/utils/util';
import { Context } from './context';

const GlossaryEntry = objectType({
    name: 'GlossaryEntry',
    definition(t) {
        t.int('id');
        t.string('name');
        t.string('definition');
        t.string('urls');
    },
});

const Query = queryType({
    definition(t) {
        t.list.field('glossary', {
            type: 'GlossaryEntry',
            async resolve(_root, args, ctx: Context) {
                return await mightFailWithArray<Entry>()(allGlossaryEntries());
            },
        });
    },
});

export const schema = makeSchema({
    types: [Query, GlossaryEntry],
    shouldGenerateArtifacts: process.env.NODE_ENV === 'development',
    outputs: {
        schema: join(process.cwd(), 'schema.graphql'),
        typegen: join(process.cwd(), 'nexus.ts'),
    },
    // sourceTypes: {
    //     modules: [{ module: '.prisma/client', alias: 'prisma' }],
    //     debug: process.env.NODE_ENV === 'development',
    // },
    contextType: {
        module: join(process.cwd(), 'graphql', 'context.ts'),
        export: 'Context',
    },
    // nonNullDefaults: {
    //     input: true,
    //     output: true,
    // },
});
