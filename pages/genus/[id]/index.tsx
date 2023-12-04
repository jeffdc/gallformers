import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { Col, Container, Row } from 'react-bootstrap';
import 'react-simple-tree-menu/dist/main.css';
import SpeciesTable from '../../../components/speciesTable';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { EMPTY_TAXONOMYENTRY, TaxonomyEntry } from '../../../libs/api/taxonomy';
import { allGenusIds, getAllSpeciesForSectionOrGenus, taxonomyEntryById } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { formatWithDescription } from '../../../libs/pages/renderhelpers';

type Props = {
    genus: TaxonomyEntry[];
    species: SimpleSpecies[];
};

const Genus = ({ genus, species }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    if (genus.length <= 0) {
        return <ErrorPage statusCode={404} />;
    }
    const gen = genus[0];
    const fam = pipe(gen.parent, O.getOrElse(constant(EMPTY_TAXONOMYENTRY)));

    const fullName = formatWithDescription(gen.name, gen.description);

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>{fullName}</title>
                <meta name="description" content={`Genus ${gen.name}`} />
            </Head>

            <Row>
                <Col>
                    <h1>
                        Genus <i>{fullName}</i>
                    </h1>
                </Col>
            </Row>
            <Row>
                <Col>
                    <strong>Family:</strong>{' '}
                    <Link key={fam.id} href={`/family/${fam.id}`}>
                        <i>{fam.name}</i>
                    </Link>
                    {` (${fam.description})`}
                </Col>
            </Row>
            <Row className="pt-3">
                <Col>
                    <SpeciesTable species={species} />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    try {
        const genus = await getStaticPropsWithContext(context, taxonomyEntryById, 'genus');
        return {
            props: {
                // must add a key so that a navigation from the same route will re-render properly
                key: genus[0].id ?? -1,
                genus: genus,
                species: await getStaticPropsWithContext(
                    context,
                    getAllSpeciesForSectionOrGenus,
                    'species for genus',
                    false,
                    true,
                ),
            },
            revalidate: 1,
        };
    } catch (e) {
        return { notFound: true };
    }
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGenusIds);

export default Genus;
