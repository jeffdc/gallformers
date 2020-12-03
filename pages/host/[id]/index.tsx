import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React, { MouseEvent, useState } from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { HostApi, HostGall } from '../../../libs/apitypes';
import { allHostIds, hostById } from '../../../libs/db/host';
import { mightBeNull } from '../../../libs/db/utils';
import { getStaticPathsFromIds, getStaticPropsWithId } from '../../../libs/pages/nextPageHelpers';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    host: HostApi;
};

function gallAsLink(g: HostGall) {
    if (!g.gallspecies) throw new Error('Recieved invalid gall for host.');

    return (
        <Link key={g.gallspecies.id} href={`/gall/${g.gallspecies.id}`}>
            <a>{g.gallspecies.name} </a>
        </Link>
    );
}

const Host = ({ host }: Props): JSX.Element => {
    const source = host.speciessource.find((s) => s.useasdefault !== 0);
    const [selectedSource, setSelectedSource] = useState(source);

    const changeDescription = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        const id = e.currentTarget.id;
        const s = host.speciessource.find((s) => s.source_id.toString() === id);
        setSelectedSource(s);
    };

    return (
        <div
            style={{
                marginBottom: '5%',
                marginRight: '5%',
            }}
        >
            <Media>
                <img width={170} height={128} className="mr-3" src="" alt={host.name} />
                <Media.Body>
                    <Container className="p-3 border">
                        <Row>
                            <Col>
                                <h2>{host.name}</h2>
                                {host.commonnames ? `(${host.commonnames})` : ''}
                            </Col>
                            Family:
                            <Link key={host.family.id} href={`/family/${host.family.id}`}>
                                <a> {host.family.name}</a>
                            </Link>
                        </Row>
                        <Row>
                            <Col className="lead p-3">{source?.description}</Col>
                        </Row>
                        <Row>
                            <Col>Galls: {host.host_galls.map(gallAsLink)}</Col>
                        </Row>
                        <Row>
                            <Col>Abdundance: {mightBeNull(host.abundance?.abundance)}</Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Further Information:</strong>
                                <ListGroup variant="flush" defaultActiveKey={selectedSource?.source_id}>
                                    {host.speciessource
                                        .sort((a, b) => a.source.citation.localeCompare(b.source.citation))
                                        .map((speciessource) => (
                                            <ListGroup.Item
                                                key={speciessource.source_id}
                                                id={speciessource.source_id.toString()}
                                                action
                                                onClick={changeDescription}
                                                variant={speciessource.source_id === selectedSource?.source_id ? 'dark' : ''}
                                            >
                                                <Link href={`/source/${speciessource.source?.id}`}>
                                                    <a>{speciessource.source?.citation}</a>
                                                </Link>
                                            </ListGroup.Item>
                                        ))}
                                </ListGroup>
                                <hr />
                                <Row className="">
                                    <Col className="align-self-center">
                                        <strong>See Also:</strong>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={iNatUrl(host.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/inatlogo-small.png" />
                                        </a>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={bugguideUrl(host.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/bugguide-small.png" />
                                        </a>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={gScholarUrl(host.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/gscholar-small.png" />
                                        </a>
                                    </Col>
                                </Row>
                            </Col>
                        </Row>
                    </Container>
                </Media.Body>
            </Media>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const host = getStaticPropsWithId(context, hostById, 'host');

    return {
        props: {
            host: await host,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allHostIds);

export default Host;
