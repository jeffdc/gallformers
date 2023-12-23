import * as O from 'fp-ts/lib/Option.js';
import { constant, pipe } from 'fp-ts/lib/function.js';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error.js';
import Head from 'next/head.js';
import { useRouter } from 'next/router.js';
import { Card, Col, Container, Row } from 'react-bootstrap';
import TreeMenu, { Item, TreeNodeInArray } from 'react-simple-tree-menu';
import 'react-simple-tree-menu/dist/main.css';
import Edit from '../../../components/edit.js';
import { TaxonCodeValues, TaxonomyEntry } from '../../../libs/api/apitypes.js';
import { TaxonomyTree, allFamilyIds, taxonomyEntryById, taxonomyTreeForId } from '../../../libs/db/taxonomy.js';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers.js';
import { formatWithDescription } from '../../../libs/pages/renderhelpers.js';
import { hasProp } from '../../../libs/utils/util.js';

type Props = {
    family: TaxonomyEntry[];
    tree: TreeNodeInArray[];
};

const Family = ({ family, tree }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    if (family.length <= 0) {
        return <ErrorPage.default statusCode={404} />;
    }

    const fam = family[0];

    const handleClick = (item: Item) => {
        if (hasProp(item, 'url')) {
            // type-coverage:ignore-next-line
            router.push(item.url as string);
        }
    };

    return (
        <Container className="pt-2" fluid>
            <Head.default>
                <title>{fam.name}</title>
                <meta name="description" content={`Family ${fam.name}`} />
            </Head.default>
            <Row>
                <Col xs={12}>
                    <Card>
                        <Card.Header>
                            <Edit id={fam.id} type="taxonomy" />
                            <h1>
                                {fam.name} - {fam.description}
                            </h1>
                        </Card.Header>
                        <Card.Body>
                            <TreeMenu.default data={tree} onClickItem={handleClick} initialOpenNodes={[fam.id.toString()]} />
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
                label: formatWithDescription(tt.name, tt.description),
                nodes: tt.speciestaxonomy
                    .sort((a, b) => a.species.name.localeCompare(b.species.name))
                    .map((st) => ({
                        key: st.species.id.toString(),
                        label: st.species.name,
                        url: `/${st.species.taxoncode === TaxonCodeValues.GALL ? 'gall' : 'host'}/${st.species.id}`,
                    })),
            })),
    },
];

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    try {
        const family = await getStaticPropsWithContext(context, taxonomyEntryById, 'family');
        if (!family[0]) throw '404';
        const tree = pipe(
            await getStaticPropsWithContext(context, taxonomyTreeForId, 'species', false, true),
            O.fold(constant([]), toTreeNodeInArray),
        );

        return {
            props: {
                // must add a key so that a navigation from the same route will re-render properly
                key: family[0].id ?? -1,
                family: family,
                tree: tree,
            },
            revalidate: 1,
        };
    } catch (e) {
        return { notFound: true };
    }
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allFamilyIds);

export default Family;
