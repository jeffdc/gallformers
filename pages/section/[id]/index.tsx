import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import Edit from '../../../components/edit';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { SectionApi } from '../../../libs/api/taxonomy';
import { allSectionIds, getSection } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

type Props = {
    section: SectionApi;
};

const linkSpecies = (cell: string, row: SimpleSpecies) => {
    return (
        <span>
            <a href={`/host/${row.id}`}>{cell}</a>
        </span>
    );
};

const columns: ColumnDescription[] = [
    {
        dataField: 'name',
        text: 'Species Name',
        sort: true,
        formatter: linkSpecies,
    },
];

const Section = ({ section }: Props): JSX.Element => {
    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    return (
        <Container className="p-2 m-2">
            <Head>
                <title>{section.name}</title>
            </Head>
            <Row>
                <Col>
                    <h2>{section.name}</h2>
                </Col>
                <Col xs={2} className="mr-1">
                    <span className="p-0 pr-1 my-auto">
                        <Edit id={section.id} type="section" />
                    </span>
                </Col>
            </Row>
            <Row>
                <Col>{section.description}</Col>
                <Col> {section.aliases.map((a) => a.name).join(', ')}</Col>
            </Row>
            <Row className="pt-2">
                <Col>
                    <BootstrapTable
                        keyField={'id'}
                        data={section.species.sort((a, b) => a.name.localeCompare(b.name))}
                        columns={columns}
                        bootstrap4
                        striped
                        headerClasses="table-header"
                        rowStyle={{ lineHeight: 1 }}
                    />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const section = await getStaticPropsWithContext(context, getSection, 'section');
    if (O.isNone(section)) throw new Error(`Failed to fetch Section with id ${context.params}`);

    return {
        props: {
            section: pipe(section, O.getOrElseW(constant(null))),
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allSectionIds);

export default Section;
