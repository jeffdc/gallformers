import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import SourceList from '../../../components/sourcelist';
import { GallSimple, HostApi } from '../../../libs/api/apitypes';
import { FGS } from '../../../libs/api/taxonomy';
import { allHostIds, hostById } from '../../../libs/db/host';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { linkTextToGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { deserialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    host: HostApi;
    taxonomy: FGS;
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

    // the galls will not be sorted, so sort them for display
    host.galls.sort((a, b) => a.name.localeCompare(b.name));
    const gallLinker = gallAsLink(host.galls.length);

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
                                                    ? 'All galls known to occur on this plant have been added to the database, and can be filtered by Location and Detachable. However, sources and images for galls associated with this host may be incomplete or absent, and other filters may not have been entered comprehensively or at all.'
                                                    : 'We are still working on this species so data might be missing.'}
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
                                    <Link key={taxonomy.family.id} href={`/family/${taxonomy.family.id}`}>
                                        <a> {taxonomy.family.name}</a>
                                    </Link>
                                    {pipe(
                                        taxonomy.section,
                                        O.map((s) => (
                                            // eslint-disable-next-line react/jsx-key
                                            <span>
                                                {' | '}
                                                <strong> Section: </strong>{' '}
                                                <Link key={s.id} href={`/section/${s.id}`}>
                                                    {`${s.name} (${s.description})`}
                                                </Link>
                                            </span>
                                        )),
                                        O.map((s) => s),
                                        O.getOrElse(constant(<></>)),
                                    )}
                                </p>
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
                <hr />
                <Row>
                    <Col id="description" className="p-3">
                        {selectedSource && selectedSource.description && (
                            <span>
                                <p className="white-space-pre-wrap description-text">{deserialize(selectedSource.description)}</p>
                                <p className="description-text">
                                    {selectedSource.externallink && (
                                        <span>
                                            Reference:{' '}
                                            <a href={selectedSource.externallink} target="_blank" rel="noreferrer">
                                                {selectedSource.externallink}
                                            </a>
                                        </span>
                                    )}
                                </p>
                            </span>
                        )}
                    </Col>
                </Row>
                <hr />
                <Row>
                    <Col>
                        <Edit id={host.id} type="speciessource" />
                        <strong>Further Information:</strong>
                    </Col>
                </Row>
                <Row>
                    <Col>
                        <SourceList
                            data={host.speciessource.map((s) => s.source)}
                            defaultSelection={selectedSource?.source}
                            onSelectionChange={(s) =>
                                setSelectedSource(host.speciessource.find((spso) => spso.source_id == s?.id))
                            }
                        />
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
    const h = await getStaticPropsWithContext(context, hostById, 'host');
    const host = h[0];
    const sources = await linkTextToGlossary(host.speciessource);
    const taxonomy = await getStaticPropsWithContext(context, taxonomyForSpecies, 'taxonomy');

    return {
        props: {
            host: { ...host, speciessource: sources },
            taxonomy: taxonomy,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allHostIds);

export default Host;
