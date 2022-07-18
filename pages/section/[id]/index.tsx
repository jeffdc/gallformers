import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { useMemo } from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import DataTable from '../../../components/DataTable';
import Edit from '../../../components/edit';
import { SimpleSpecies } from '../../../libs/api/apitypes';
import { SectionApi } from '../../../libs/api/taxonomy';
import { allSectionIds, sectionById } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    sec: SectionApi[];
};

const linkSpecies = (row: SimpleSpecies) => {
    return (
        <span>
            <a href={`/host/${row.id}`}>
                <i>{row.name}</i>
            </a>
        </span>
    );
};

const Section = ({ sec }: Props): JSX.Element => {
    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: SimpleSpecies) => row.name,
                name: 'Species Name',
                sortable: true,
                format: linkSpecies,
            },
        ],
        [],
    );

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    if (!sec) {
        return <ErrorPage statusCode={404} />;
    }

    const section = sec[0];

    const fullName = section.description ? `${section.name} (${section.description})` : section.name;

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>{fullName}</title>
                <meta name="description" content={`Section ${fullName}`} />
            </Head>
            <Row>
                <Col>
                    <h2>{fullName}</h2>
                </Col>
                <Col xs={2} className="me-1">
                    <span className="p-0 pe-1 my-auto">
                        <Edit id={section.id} type="section" />
                    </span>
                </Col>
            </Row>
            <Row className="pt-2">
                <Col>
                    <DataTable
                        keyField={'id'}
                        data={section.species.sort((a, b) => a.name.localeCompare(b.name))}
                        columns={columns}
                        striped
                        noHeader
                        fixedHeader
                        responsive={false}
                        defaultSortFieldId="name"
                        customStyles={TABLE_CUSTOM_STYLES}
                    />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const section = await getStaticPropsWithContext(context, sectionById, 'section');

    if (!section || section.length <= 0) {
        return { notFound: true };
    }

    return {
        props: {
            // must add a key so that a navigation from the same route will re-render properly
            key: section[0]?.id ?? -1,
            sec: section,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allSectionIds);

export default Section;
