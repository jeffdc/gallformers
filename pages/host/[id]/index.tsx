import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React, { MouseEvent, useState } from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { GallSimple, HostApi } from '../../../libs/api/apitypes';
import { allHostIds, hostById } from '../../../libs/db/host';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { renderCommonNames } from '../../../libs/pages/renderhelpers';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    host: HostApi;
};

// eslint-disable-next-line react/display-name
const gallAsLink = (len: number) => (g: GallSimple, idx: number) => {
    if (!g) throw new Error('Recieved invalid gall for host.');

    return (
        <Link key={g.id} href={`/gall/${g.id}`}>
            <a>
                {g.name} {idx < len - 1 ? ' / ' : ''}
            </a>
        </Link>
    );
};

const Host = ({ host }: Props): JSX.Element => {
    // the galls will not be sorted, so sort them for display
    host.galls.sort((a, b) => a.name.localeCompare(b.name));
    const gallLinker = gallAsLink(host.galls.length);

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
                    <Container className="p-3">
                        <Row>
                            <Col>
                                <h2>{host.name}</h2>
                                {renderCommonNames(host.commonnames)}
                            </Col>
                            Family:
                            <Link key={host.family.id} href={`/family/${host.family.id}`}>
                                <a> {host.family.name}</a>
                            </Link>
                        </Row>
                        <Row>
                            <Col className="lead p-3">
                                {selectedSource?.description == undefined
                                    ? ''
                                    : pipe(selectedSource.description, O.getOrElse(constant('')))}
                            </Col>
                        </Row>
                        <Row>
                            <Col>Galls: {host.galls.map(gallLinker)}</Col>
                        </Row>
                        <Row>
                            <Col>
                                Abdundance:{' '}
                                {pipe(
                                    host.abundance,
                                    O.map((a) => a.abundance),
                                    O.getOrElse(constant('')),
                                )}
                            </Col>
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
    const host = getStaticPropsWithContext(context, hostById, 'host');

    return {
        props: {
            host: (await host)[0],
        },
        revalidate: 60,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allHostIds);

export default Host;
