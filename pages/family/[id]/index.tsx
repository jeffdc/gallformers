import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React from 'react';
import { Card, Col, Container, Row } from 'react-bootstrap';
import TreeMenu, { Item, TreeNodeInArray } from 'react-simple-tree-menu';
import 'react-simple-tree-menu/dist/main.css';
import Edit from '../../../components/edit';
import { GallTaxon } from '../../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyTree } from '../../../libs/api/taxonomy';
import { allFamilyIds, taxonomyEntryById, taxonomyTreeForId } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { hasProp } from '../../../libs/utils/util';

type Props = {
    family: O.Option<TaxonomyEntry>;
    tree: TreeNodeInArray[];
};

const Family = ({ family, tree }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    if (O.isNone(family)) {
        return <ErrorPage statusCode={404} />;
    }
    const fam = pipe(family, O.getOrElse(constant({} as TaxonomyEntry)));

    const handleClick = (item: Item) => {
        if (hasProp(item, 'url')) {
            router.push(item.url as string);
        }
    };

    return (
        <Container className="p-2 m-2">
            <Head>
                <title>{fam.name}</title>
            </Head>
            <Row>
                <Col xs={12}>
                    <Card>
                        <Card.Header>
                            <Edit id={fam.id} type="family" />
                            <h1>
                                {fam.name} - {fam.description}
                            </h1>
                        </Card.Header>
                        <Card.Body>
                            <TreeMenu data={tree} onClickItem={handleClick} initialOpenNodes={[fam.id.toString()]} />
                        </Card.Body>
                    </Card>
                </Col>
            </Row>
        </Container>
    );
};

const toTreeNodeInArray = (tree: TaxonomyTree): TreeNodeInArray[] => [
    {
        key: tree.id.toString(),
        label: tree.name,
        nodes: tree.taxonomy
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
    },
];

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const family = await getStaticPropsWithContext(context, taxonomyEntryById, 'family');
    const tree = pipe(
        await getStaticPropsWithContext(context, taxonomyTreeForId, 'species', false, true),
        O.fold(constant([]), toTreeNodeInArray),
    );

    return {
        props: {
            family: family,
            tree: tree,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allFamilyIds);

export default Family;
