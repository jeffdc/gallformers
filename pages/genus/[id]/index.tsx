import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import 'react-simple-tree-menu/dist/main.css';
import SpeciesTable from '../../../components/speciesTable';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { TaxonomyEntry } from '../../../libs/api/taxonomy';
import { allGenusIds, getAllSpeciesForSectionOrGenus, taxonomyEntryById } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { formatWithDescription } from '../../../libs/pages/renderhelpers';

type Props = {
    genus: O.Option<TaxonomyEntry>;
    species: SimpleSpecies[];
};

const Genus = ({ genus, species }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    if (O.isNone(genus)) {
        return <ErrorPage statusCode={404} />;
    }
    const gen = pipe(genus, O.getOrElse(constant({} as TaxonomyEntry)));
    const fam = pipe(gen.parent, O.getOrElse(constant({} as TaxonomyEntry)));

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
                        <a>
                            <i>{fam.name}</i>
                        </a>
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
    return {
        props: {
            genus: await getStaticPropsWithContext(context, taxonomyEntryById, 'genus'),
            species: await getStaticPropsWithContext(context, getAllSpeciesForSectionOrGenus, 'species for genus', false, true),
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGenusIds);

export default Genus;
