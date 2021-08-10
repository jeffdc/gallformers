import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Alert, Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';
import remarkBreaks from 'remark-breaks';
import externalLinks from 'remark-external-links';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import InfoTip from '../../../components/infotip';
import SeeAlso from '../../../components/seealso';
import SourceList from '../../../components/sourcelist';
import { DetachableBoth, GallApi, GallHost, SimpleSpecies } from '../../../libs/api/apitypes';
import { FGS } from '../../../libs/api/taxonomy';
import { allGallIds, gallById, getRelatedGalls } from '../../../libs/db/gall';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { linkSourceToGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWith, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { createSummaryGall, defaultSource, formatLicense, sourceToDisplay } from '../../../libs/pages/renderhelpers';

type Props = {
    species: GallApi;
    taxonomy: FGS;
    relatedGalls: SimpleSpecies[];
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

const Gall = ({ species, taxonomy, relatedGalls }: Props): JSX.Element => {
    const [selectedSource, setSelectedSource] = useState(defaultSource(species?.speciessource));
    const [notesAlertShown, setNotesAlertShown] = useState(true);

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

    const notesSpeciesSource = species.speciessource?.find((s) => s.source?.id === 58);

    return (
        <Container className="pt-2 fluid">
            <Head>
                <title>{species.name}</title>
                <meta name="description" content={`${species.name} - ${createSummaryGall(species)}`} />
            </Head>
            <Row className="mt-2">
                {/* Details */}
                <Col sm={12} md={8}>
                    <Row>
                        <Col>
                            <Row>
                                <Col>
                                    <h2 className="font-italic">{species.name}</h2>
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
                                <Col className="font-italic"> {species.aliases.map((a) => a.name).join(', ')}</Col>
                            </Row>
                            <Row>
                                <Col>
                                    <strong>Family:</strong>
                                    <Link key={taxonomy.family.id} href={`/family/${taxonomy.family.id}`}>
                                        <a> {taxonomy.family.name}</a>
                                    </Link>
                                    {' | '}
                                    <strong>Genus:</strong>
                                    <Link key={taxonomy.genus.id} href={`/genus/${taxonomy.genus.id}`}>
                                        <a className="font-italic"> {taxonomy.genus.name}</a>
                                    </Link>
                                </Col>
                            </Row>
                            <Row className="">
                                <Col>
                                    <strong>Hosts:</strong> {species.hosts.map(hostLinker)}
                                    <Edit id={species.id} type="gallhost" />
                                </Col>
                            </Row>
                            <Row>
                                <Col xs={6} sm={4}>
                                    <strong>Detachable:</strong> {species.gall.detachable.value}
                                    {species.gall.detachable.value === DetachableBoth.value && (
                                        <InfoTip
                                            id="detachable"
                                            text="This gall can be both detachable and integral depending on what stage of its lifecycle it is in."
                                        />
                                    )}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Color:</strong> {species.gall.gallcolor.map((c) => c.field).join(', ')}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Texture:</strong> {species.gall.galltexture.map((t) => t.field).join(', ')}
                                </Col>
                            </Row>
                            <Row>
                                <Col xs={6} sm={4}>
                                    <strong>Alignment:</strong> {species.gall.gallalignment.map((a) => a.field).join(', ')}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Walls:</strong> {species.gall.gallwalls.map((w) => w.field).join(', ')}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Location:</strong> {species.gall.galllocation.map((l) => l.field).join(', ')}
                                </Col>
                            </Row>
                            <Row>
                                <Col xs={6} sm={4}>
                                    <strong>Abdundance:</strong>{' '}
                                    {pipe(
                                        species.abundance,
                                        O.fold(constant(''), (a) => a.abundance),
                                    )}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Shape:</strong> {species.gall.gallshape.map((s) => s.field).join(', ')}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Season:</strong> {species.gall.gallseason.map((s) => s.field).join(', ')}
                                </Col>
                            </Row>
                            <Row>
                                <Col xs={6} sm={4}>
                                    <strong>Form:</strong> {species.gall.gallform.map((s) => s.field).join(', ')}
                                </Col>
                                <Col xs={6} sm={4}>
                                    <strong>Cells:</strong> {species.gall.gallcells.map((s) => s.field).join(', ')}
                                </Col>
                                <Col>
                                    <strong>Related: </strong>
                                    {relatedGalls.map((g, i) => (
                                        <span key={g.id}>
                                            {' '}
                                            <Link key={g.id} href={`/gall/${g.id}`}>
                                                <a>{g.name}</a>
                                            </Link>
                                            {i < relatedGalls.length - 1 ? ', ' : ''}
                                        </span>
                                    ))}
                                </Col>
                            </Row>
                        </Col>
                    </Row>
                </Col>
                {/* Images */}
                <Col sm={{ span: 12 }} md={4}>
                    <Images sp={species} type="gall" />
                </Col>
                {/* Description */}
                <Col>
                    <Row>
                        <Col>
                            <hr />
                        </Col>
                    </Row>
                    <Row hidden={!notesAlertShown || !(notesSpeciesSource && notesSpeciesSource.id !== selectedSource?.id)}>
                        <Col id="notes-reminder">
                            <Alert variant="info" dismissible onClose={() => setNotesAlertShown(false)}>
                                Our ID Notes may contain important tips necessary for distinguishing this gall from similar galls
                                and/or important information about the taxonomic status of this gall inducer.
                                <Button
                                    className="ml-3"
                                    variant="outline-info"
                                    size="sm"
                                    onClick={() => setSelectedSource(notesSpeciesSource)}
                                >
                                    Show notes
                                </Button>
                            </Alert>
                        </Col>
                    </Row>
                    <Row>
                        <Col id="description" className="lead p-3">
                            {selectedSource && selectedSource.description && (
                                <span>
                                    <span className="source-quotemark">&ldquo;</span>
                                    <ReactMarkdown rehypePlugins={[rehypeRaw]} remarkPlugins={[externalLinks, remarkBreaks]}>
                                        {selectedSource.description}
                                    </ReactMarkdown>
                                    <span className="source-quotemark">&rdquo;</span>
                                    <p>
                                        <i>- {sourceToDisplay(selectedSource.source)}</i>
                                        <InfoTip
                                            id="copyright"
                                            text={`Source entries are edited for relevance, brevity, and formatting. All text is quoted from the selected source except where noted by [brackets].\nThis source: ${formatLicense(
                                                selectedSource.source,
                                            )}.`}
                                            tip="©"
                                        />
                                    </p>
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
                </Col>
            </Row>
            <Row>
                <Col>
                    <hr />
                </Col>
            </Row>
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
                    <Row>
                        <Col className="align-self-center">
                            <strong>See Also:</strong>
                        </Col>
                    </Row>
                    <SeeAlso name={species.name} />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const g = await getStaticPropsWithContext(context, gallById, 'gall');
    const gall = g[0];
    const sources = gall ? await linkSourceToGlossary(gall.speciessource) : null;
    const fgs = gall ? await getStaticPropsWithContext(context, taxonomyForSpecies, 'taxonomy') : null;
    const relatedGalls = gall ? await getStaticPropsWith<SimpleSpecies>(() => getRelatedGalls(gall), 'related galls') : null;

    return {
        props: {
            species: gall ? { ...gall, speciessource: sources } : null,
            taxonomy: fgs,
            relatedGalls: relatedGalls,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGallIds);

export default Gall;
