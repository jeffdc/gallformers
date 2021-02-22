import { taxonomy } from '@prisma/client';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React from 'react';
import { Card, Col, Container, Row } from 'react-bootstrap';
import TreeMenu, { Item, TreeNodeInArray } from 'react-simple-tree-menu';
import 'react-simple-tree-menu/dist/main.css';
import Edit from '../../../components/edit';
import { GallTaxon } from '../../../libs/api/apitypes';
import { allFamilyIds, taxonomyById, taxonomyForId } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { hasProp } from '../../../libs/utils/util';

type Props = {
    family: taxonomy;
    tree: TreeNodeInArray[];
};

const Family = ({ family, tree }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    const handleClick = (item: Item) => {
        console.log(JSON.stringify(item, null, ' '));
        if (hasProp(item, 'url')) {
            router.push(item.url as string);
        }
    };

    return (
        <div
            style={{
                marginBottom: '5%',
                marginRight: '5%',
            }}
        >
            <Head>
                <title>{family.name}</title>
            </Head>

            <Card className="ml-3">
                <Card.Header>
                    <Edit id={family.id} type="family" />
                    <h1>
                        {family.name} - {family.description}
                    </h1>
                </Card.Header>
                <Card.Body>
                    <TreeMenu data={tree} onClickItem={handleClick} initialOpenNodes={[family.id.toString()]} />
                </Card.Body>
            </Card>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const family = getStaticPropsWithContext(context, taxonomyById, 'family');
    const taxonomy = await getStaticPropsWithContext(context, taxonomyForId, 'species', false, true);
    const tree: TreeNodeInArray[] = taxonomy.map((t) => ({
        key: t.id.toString(),
        label: t.name,
        nodes: t.taxonomy
            .sort((a, b) => a.name.localeCompare(b.name))
            .map((tt) => ({
                key: tt.id.toString(),
                label: tt.name,
                nodes: tt.speciestaxonomy
                    .sort((a, b) => a.species.name.localeCompare(b.species.name))
                    .map((st) => ({
                        key: st.species.id.toString(),
                        label: st.species.name,
                        url: `/${st.species.taxoncode === GallTaxon ? 'gall' : 'host'}/${st.species.id}`,
                    })),
            })),
    }));

    return {
        props: {
            family: (await family)[0],
            tree: tree,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allFamilyIds);

export default Family;
