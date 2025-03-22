import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { useMemo } from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import DataTable, { TableColumn } from 'react-data-table-component';
import Edit from '../../../components/edit';
import { HostSimple, PlaceWithHostsApi } from '../../../libs/api/apitypes';
import { allPlaceIds, placeById } from '../../../libs/db/place.ts';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    place: PlaceWithHostsApi;
};

const linkPlant = (row: HostSimple) => {
    return (
        <span>
            <a href={`/host/${row.id}`}>
                <i>{row.name}</i>
            </a>
        </span>
    );
};

const PlacePage = ({ place }: Props): JSX.Element => {
    const columns = useMemo<TableColumn<HostSimple>[]>(
        () => [
            {
                id: 'name',
                selector: (row: HostSimple) => row.name,
                name: 'Species Name',
                sortable: true,
                format: linkPlant,
            },
            {
                id: 'hosts',
                // UGGH
                // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                //@ts-ignore
                selector: (row: HostSimple) => row.aliases,
                name: 'Aliases',
                sortable: true,
                format: (row: HostSimple) => row.aliases.map((a) => a.name).join(', '),
            },
        ],
        [],
    );

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>{place.name}</title>
                <meta name="description" content={`Place ${place.name}`} />
            </Head>
            <Row>
                <Col>
                    <h2>{`${place.name} - ${place.code}`}</h2>
                </Col>
                <Col xs={2} className="me-1">
                    <span className="p-0 pe-1 my-auto">
                        <Edit id={place.id} type="place" />
                    </span>
                </Col>
            </Row>
            <Row>
                <Col>
                    {place.parent.length > 0
                        ? `a ${place.type} of ${place.parent[0].name === 'United States' ? 'the' : ''} ${place.parent[0].name}`
                        : ''}
                </Col>
            </Row>
            <Row className="pt-2">
                <Col>
                    <DataTable
                        keyField={'id'}
                        data={place.hosts.sort((a, b) => a.name.localeCompare(b.name))}
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
            <Row>
                <Col>
                    <br />
                    <br />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    try {
        const place = await getStaticPropsWithContext(context, placeById, 'place');
        if (!place[0]) throw new Error('404');

        return {
            props: {
                // must add a key so that a navigation from the same route will re-render properly
                key: place[0]?.id,
                place: place[0],
            },
            revalidate: 1,
        };
    } catch {
        return { notFound: true };
    }
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allPlaceIds);

export default PlacePage;
