import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import ErrorPage from 'next/error';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import InfoTip from '../../../components/infotip';
import SourceList from '../../../components/sourcelist';
import { CCBY, DetachableBoth, GallApi, GallHost } from '../../../libs/api/apitypes';
import { FGS } from '../../../libs/api/taxonomy';
import { allGallIds, gallById } from '../../../libs/db/gall';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { linkTextToGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { defaultSource, formatLicense } from '../../../libs/pages/renderhelpers';
import { deserialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    species: GallApi;
    taxonomy: FGS;
};

// eslint-disable-next-line react/display-name
const hostAsLink = (len: number) => (h: GallHost, idx: number) => {
    return (
        <Link key={h.id} href={`/host/${h.id}`}>
            <a>
                {h.name} {idx < len - 1 ? ' / ' : ''}
            </a>
        </Link>
    );
};

const Gall = ({ species, taxonomy }: Props): JSX.Element => {
    const [selectedSource, setSelectedSource] = useState(defaultSource(species?.speciessource));

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    } else if (species == null) {
        return <ErrorPage statusCode={404} />;
    }

    // the hosts will not be sorted, so sort them for display
    species.hosts.sort((a, b) => a.name.localeCompare(b.name));
    const hostLinker = hostAsLink(species.hosts.length);

    return (
        <div
            style={{
                marginBottom: '5%',
                marginRight: '5%',
            }}
        >
            <Head>
                <title>{species.name}</title>
            </Head>
            <Container className="p-1">
                <Row>
                    {/* The Details Column */}
                    <Col>
                        <Row>
                            <Col className="">
                                <h2>{species.name}</h2>
                            </Col>
                            <Col xs={2}>
                                <span className="p-0 pr-1 my-auto">
                                    <Edit id={species.id} type="gall" />
                                    <OverlayTrigger
                                        placement="right"
                                        overlay={
                                            <Tooltip id="datacomplete">
                                                {species.datacomplete
                                                    ? 'All sources containing unique information relevant to this gall have been added and are reflected in its associated data. However, filter criteria may not be comprehensive in every field.'
                                                    : 'We are still working on this species so data is missing.'}
                                            </Tooltip>
                                        }
                                    >
                                        <Button variant="outline-light">{species.datacomplete ? '💯' : '❓'}</Button>
                                    </OverlayTrigger>
                                </span>
                            </Col>
                        </Row>
                        <Row hidden={!species.gall.undescribed}>
                            <Col>
                                <span className="text-danger">This is an undescribed species.</span>
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                {species.aliases.map((a) => a.name).join(', ')}
                                <p className="font-italic">
                                    <strong>Family:</strong>
                                    <Link key={taxonomy.family.id} href={`/family/${taxonomy.family.id}`}>
                                        <a> {taxonomy.family.name}</a>
                                    </Link>
                                </p>
                            </Col>
                        </Row>
                        <Row className="">
                            <Col>
                                <strong>Hosts:</strong> {species.hosts.map(hostLinker)}
                                <Edit id={species.id} type="gallhost" />
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Detachable:</strong> {species.gall.detachable.value}
                                {species.gall.detachable.value === DetachableBoth.value && (
                                    <InfoTip
                                        id="detachable"
                                        text="This gall can be both detachable and integral depending on what stage of its lifecycle it is in."
                                    />
                                )}
                            </Col>
                            <Col>
                                <strong>Color:</strong> {species.gall.gallcolor.map((c) => c.color).join(', ')}
                            </Col>
                            <Col>
                                <strong>Texture:</strong> {species.gall.galltexture.map((t) => t.tex).join(', ')}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Alignment:</strong> {species.gall.gallalignment.map((a) => a.alignment).join(', ')}
                            </Col>
                            <Col>
                                <strong>Walls:</strong> {species.gall.gallwalls.map((w) => w.walls).join(', ')}
                            </Col>
                            <Col>
                                <strong>Location:</strong> {species.gall.galllocation.map((l) => l.loc).join(', ')}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Abdundance:</strong>{' '}
                                {pipe(
                                    species.abundance,
                                    O.fold(constant(''), (a) => a.abundance),
                                )}
                            </Col>
                            <Col>
                                <strong>Shape:</strong> {species.gall.gallshape.map((s) => s.shape).join(', ')}
                            </Col>
                            <Col>
                                <strong>Season:</strong> {species.gall.gallseason.map((s) => s.season).join(', ')}
                            </Col>
                        </Row>
                    </Col>
                    <Col xs={4} className="border rounded p-1 mx-auto">
                        <Images species={species} type="gall" />
                    </Col>
                </Row>
                <Row>
                    <Col>
                        <hr />
                    </Col>
                </Row>
                <Row>
                    <Col id="description" className="lead p-3">
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
                                <p>
                                    <InfoTip
                                        id="copyright"
                                        text={`Source entries are edited for relevance, brevity, and formatting. All text is quoted from the selected source except where noted by [brackets]. This source: ${formatLicense(
                                            selectedSource.source,
                                        )}.`}
                                        tip="© Info"
                                    />
                                </p>
                            </span>
                        )}
                    </Col>
                </Row>
                <hr />
                <Row>
                    <Col>
                        <Edit id={species.id} type="speciessource" />
                        <strong>Further Information:</strong>
                    </Col>
                </Row>
                <Row>
                    <Col>
                        <SourceList
                            data={species.speciessource.map((s) => s.source)}
                            defaultSelection={selectedSource?.source}
                            onSelectionChange={(s) =>
                                setSelectedSource(species.speciessource.find((spso) => spso.source_id == s?.id))
                            }
                        />
                        <hr />
                        <Row className="">
                            <Col className="align-self-center">
                                <strong>See Also:</strong>
                            </Col>
                            <Col className="align-self-center">
                                <a href={iNatUrl(species.name)} target="_blank" rel="noreferrer">
                                    <img src="/images/inatlogo-small.png" />
                                </a>
                            </Col>
                            <Col className="align-self-center">
                                <a href={bugguideUrl(species.name)} target="_blank" rel="noreferrer">
                                    <img src="/images/bugguide-small.png" />
                                </a>
                            </Col>
                            <Col className="align-self-center">
                                <a href={gScholarUrl(species.name)} target="_blank" rel="noreferrer">
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
    const g = await getStaticPropsWithContext(context, gallById, 'gall');
    const gall = g[0];
    const sources = gall ? await linkTextToGlossary(gall.speciessource) : null;
    const fgs = gall ? await getStaticPropsWithContext(context, taxonomyForSpecies, 'taxonomy') : null;

    return {
        props: {
            species: gall ? { ...gall, speciessource: sources } : null,
            taxonomy: fgs,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGallIds);

export default Gall;
