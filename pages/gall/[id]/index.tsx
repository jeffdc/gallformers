import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import ErrorPage from 'next/error';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import InfoTip from '../../../components/infotip';
import RangeMap from '../../../components/rangemap';
import SeeAlso from '../../../components/seealso';
import SourceList from '../../../components/sourcelist';
import SpeciesSynonymy from '../../../components/speciesSynonymy';
import { DetachableBoth, GallApi, GallHost, GallTaxon, SimpleSpecies } from '../../../libs/api/apitypes';
import { FGS } from '../../../libs/api/taxonomy';
import { allGallIds, gallById, getRelatedGalls } from '../../../libs/db/gall';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { linkSourceToGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWith, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { createSummaryGall, defaultSource, formatWithDescription } from '../../../libs/pages/renderhelpers';

type Props = {
    species: GallApi;
    taxonomy: FGS;
    relatedGalls: SimpleSpecies[];
};

// eslint-disable-next-line react/display-name
const hostAsLink = (len: number) => (h: GallHost, idx: number) => {
    return (
        <span key={h.id}>
            <Link href={`/host/${h.id}`}>{h.name}</Link>
            {idx < len - 1 ? ' / ' : ''}
        </span>
    );
};

const Gall = ({ species, taxonomy, relatedGalls }: Props): JSX.Element => {
    const router = useRouter();
    const defSource = defaultSource(species?.speciessource, router.query.source);
    const [selectedSource, setSelectedSource] = useState(defSource);

    const range = new Set<string>();
    species?.hosts.flatMap((gh) => gh.places.forEach((p) => range.add(p.code)));
    species?.excludedPlaces.forEach((p) => range.delete(p.code));

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
                                    <h2>
                                        <em>{species.name}</em>
                                    </h2>
                                </Col>
                                <Col xs={2}>
                                    <span className="p-0 pe-1 my-auto">
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
                                    <span className="text-danger">The inducer of this gall is unknown or undescribed.</span>
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <strong>Family: </strong>
                                    <Link key={taxonomy.family.id} href={`/family/${taxonomy.family.id}`}>
                                        {taxonomy.family.name}
                                    </Link>
                                    {' | '}
                                    <strong>Genus: </strong>
                                    <Link key={taxonomy.genus.id} href={`/genus/${taxonomy.genus.id}`}>
                                        {formatWithDescription(taxonomy.genus.name, taxonomy.genus.description)}
                                    </Link>
                                </Col>
                            </Row>
                            <Row className="">
                                <Col>
                                    <strong>Hosts:</strong> <em>{species.hosts.map(hostLinker)}</em>
                                    <Edit id={species.id} type="gallhost" />
                                </Col>
                            </Row>
                            <Row>
                                <Col xs={12} md={6} lg={4}>
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
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Color:</strong> {species.gall.gallcolor.map((c) => c.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Texture:</strong> {species.gall.galltexture.map((t) => t.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Abundance:</strong>{' '}
                                            {pipe(
                                                species.abundance,
                                                O.fold(constant(''), (a) => a.abundance),
                                            )}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Shape:</strong> {species.gall.gallshape.map((s) => s.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Season:</strong> {species.gall.gallseason.map((s) => s.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Related: </strong>
                                            {relatedGalls.map((g, i) => (
                                                <span key={g.id}>
                                                    {' '}
                                                    <Link key={g.id} href={`/gall/${g.id}`}>
                                                        {g.name}
                                                    </Link>
                                                    {i < relatedGalls.length - 1 ? ', ' : ''}
                                                </span>
                                            ))}
                                        </Col>
                                    </Row>
                                </Col>
                                <Col xs={12} md={6} lg={4}>
                                    <Row>
                                        <Col>
                                            <strong>Alignment:</strong>{' '}
                                            {species.gall.gallalignment.map((a) => a.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Walls:</strong> {species.gall.gallwalls.map((w) => w.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Location:</strong> {species.gall.galllocation.map((l) => l.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Form:</strong> {species.gall.gallform.map((s) => s.field).join(', ')}
                                        </Col>
                                    </Row>
                                    <Row>
                                        <Col>
                                            <strong>Cells:</strong> {species.gall.gallcells.map((s) => s.field).join(', ')}
                                        </Col>
                                    </Row>
                                </Col>
                                <Col xs={12} lg={4} className="p-0 m-0">
                                    <strong>Possible Range:</strong>
                                    <InfoTip
                                        id="rangetip"
                                        text="The gall's range is computed from the range of all hosts that the gall occurs on. In some cases we have evidence that the gall does not occur across the full range of the hosts and we will remove these places from the range. For undescribed species we will show the expected range based on hosts plus where the galls have been observed. All of this said, the exact ranges for most galls is uncertain."
                                    />
                                    <RangeMap range={range} />
                                </Col>
                            </Row>
                        </Col>
                    </Row>
                    <Row>
                        <Col>
                            <SpeciesSynonymy aliases={species.aliases} showAll={true} />
                        </Col>
                    </Row>
                </Col>
                {/* Images */}
                <Col sm={{ span: 12 }} md={4}>
                    <Row>
                        <Col>
                            <Images sp={species} type="gall" />
                        </Col>
                    </Row>
                </Col>
                {/* Description */}
                <Col>
                    <Row>
                        <Col>
                            <hr />
                        </Col>
                    </Row>
                </Col>
            </Row>
            <Row>
                <Col>
                    <SourceList
                        data={species.speciessource}
                        defaultSelection={selectedSource}
                        onSelectionChange={(s) =>
                            setSelectedSource(species.speciessource.find((spso) => spso.source_id == s?.id))
                        }
                        taxonType={GallTaxon}
                    />
                    <hr />
                    <Row>
                        <Col className="align-self-center">
                            <strong>See Also:</strong>
                        </Col>
                    </Row>
                    <SeeAlso name={species.name} undescribed={species.gall.undescribed} />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    try {
        const g = await getStaticPropsWithContext(context, gallById, 'gall');
        if (!g[0]) throw '404';

        const gall = g[0];
        const sources = gall ? await linkSourceToGlossary(gall.speciessource) : null;
        const fgs = gall ? await getStaticPropsWithContext(context, taxonomyForSpecies, 'taxonomy') : null;
        const relatedGalls = gall ? await getStaticPropsWith<SimpleSpecies>(() => getRelatedGalls(gall), 'related galls') : null;

        return {
            props: {
                // must add a key so that a navigation from the same route will re-render properly
                key: gall.id,
                species: gall ? { ...gall, speciessource: sources } : null,
                taxonomy: fgs,
                relatedGalls: relatedGalls,
            },
            revalidate: 1,
        };
    } catch (e) {
        return { notFound: true };
    }
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGallIds);

export default Gall;
