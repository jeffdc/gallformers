import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { MouseEvent, useState } from 'react';
import { Button, Col, Container, ListGroup, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import { GallSimple, HostApi, SECTION, TaxTreeForSpecies } from '../../../libs/api/apitypes';
import { allHostIds, hostById } from '../../../libs/db/host';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { deserialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    host: HostApi;
    taxonomy: TaxTreeForSpecies;
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

const Host = ({ host, taxonomy }: Props): JSX.Element => {
    const source = host ? host.speciessource.find((s) => s.useasdefault !== 0) : undefined;
    const [selectedSource, setSelectedSource] = useState(source);

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    const family = taxonomy.taxonomy.parent != null ? taxonomy.taxonomy.parent : { id: -1, name: '' };
    const section = taxonomy.taxonomy.taxonomy.find((t) => t.type === SECTION);

    // the galls will not be sorted, so sort them for display
    host.galls.sort((a, b) => a.name.localeCompare(b.name));
    const gallLinker = gallAsLink(host.galls.length);

    const changeDescription = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        const id = e.currentTarget.id;
        const s = host.speciessource.find((s) => s.source_id.toString() === id);
        setSelectedSource(s);
    };

    return (
        <div>
            <Head>
                <title>{host.name}</title>
            </Head>

            <Container className="p-1">
                <Row>
                    {/* The details column */}
                    <Col>
                        <Row>
                            <Col className="">
                                <h2>{host.name}</h2>
                            </Col>
                            <Col xs={2} className="mr-1">
                                <span className="p-0 pr-1 my-auto">
                                    <Edit id={host.id} type="host" />
                                    <OverlayTrigger
                                        placement="right"
                                        overlay={
                                            <Tooltip id="datacomplete">
                                                {host.datacomplete
                                                    ? 'The data for this species is as complete as we can make it.'
                                                    : 'We are still working on this species so data is missing.'}
                                            </Tooltip>
                                        }
                                    >
                                        <Button variant="outline-light">{host.datacomplete ? '💯' : '❓'}</Button>
                                    </OverlayTrigger>
                                </span>
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                {host.aliases.map((a) => a.name).join(', ')}
                                <p className="font-italic">
                                    <strong>Family:</strong>
                                    <Link key={family.id} href={`/family/${family.id}`}>
                                        <a> {family.name}</a>
                                    </Link>
                                    {section && (
                                        <span>
                                            <strong> Section: </strong> {section.name}
                                        </span>
                                    )}
                                </p>
                            </Col>
                        </Row>
                        <Row>
                            <Col className="">
                                {selectedSource && selectedSource.description && (
                                    <span>
                                        <p className="small white-space-pre-wrap">{deserialize(selectedSource.description)}</p>
                                        <a className="small" href={selectedSource.externallink} target="_blank" rel="noreferrer">
                                            {selectedSource.externallink}
                                        </a>
                                    </span>
                                )}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Galls:</strong> {host.galls.map(gallLinker)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Abdundance:</strong>{' '}
                                {pipe(
                                    host.abundance,
                                    O.map((a) => a.abundance),
                                    O.getOrElse(constant('')),
                                )}
                            </Col>
                        </Row>
                    </Col>

                    <Col xs={4} className="border rounded p-1 mx-auto">
                        <Images species={host} type="host" />
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
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const host = getStaticPropsWithContext(context, hostById, 'host');
    const taxonomy = getStaticPropsWithContext(context, taxonomyForSpecies, 'taxonomy');

    return {
        props: {
            host: (await host)[0],
            taxonomy: await taxonomy,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allHostIds);

export default Host;
