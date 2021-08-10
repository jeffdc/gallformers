import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Container, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription } from 'react-bootstrap-table-next';
import paginationFactory from 'react-bootstrap-table2-paginator';
import Edit from '../../../components/edit';
import { HostSimple, PlaceWithHostsApi } from '../../../libs/api/apitypes';
import { allPlaceIds, placeById } from '../../../libs/db/place';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';

type Props = {
    place: PlaceWithHostsApi;
};

const linkPlant = (cell: string, row: HostSimple) => {
    return (
        <span>
            <a href={`/host/${row.id}`}>{cell}</a>
        </span>
    );
};

const columns: ColumnDescription[] = [
    {
        dataField: 'name',
        text: 'Plant',
        sort: true,
        formatter: linkPlant,
    },
    {
        dataField: 'hosts',
        text: 'Aliases',
        formatter: (cell: string, row: HostSimple) => row.aliases.map((a) => a.name).join(', '),
    },
];

const PlacePage = ({ place }: Props): JSX.Element => {
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
                <Col xs={2} className="mr-1">
                    <span className="p-0 pr-1 my-auto">
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
                    <BootstrapTable
                        keyField={'id'}
                        data={place.hosts.sort((a, b) => a.name.localeCompare(b.name))}
                        columns={columns}
                        bootstrap4
                        striped
                        headerClasses="table-header"
                        rowStyle={{ lineHeight: 1 }}
                        pagination={paginationFactory({
                            alwaysShowAllBtns: true,
                            withFirstAndLast: false,
                            sizePerPageList: [
                                { text: '20', value: 20 },
                                { text: '50', value: 50 },
                                { text: 'All', value: place.hosts.length },
                            ],
                        })}
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
    const place = await getStaticPropsWithContext(context, placeById, 'place');

    return {
        props: {
            place: place[0],
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allPlaceIds);

export default PlacePage;
