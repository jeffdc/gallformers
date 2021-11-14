import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useMemo, useState } from 'react';
import { Button, Col, Container, OverlayTrigger, Row, Tooltip } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import ReactMarkdown from 'react-markdown';
import rehypeRaw from 'rehype-raw';
import remarkBreaks from 'remark-breaks';
import externalLinks from 'remark-external-links';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import InfoTip from '../../../components/infotip';
import SeeAlso from '../../../components/seealso';
import SourceList from '../../../components/sourcelist';
import SpeciesSynonymy from '../../../components/speciesSynonymy';
import { GallSimple, HostApi } from '../../../libs/api/apitypes';
import { FGS } from '../../../libs/api/taxonomy';
import { allHostIds, hostById } from '../../../libs/db/host';
import { taxonomyForSpecies } from '../../../libs/db/taxonomy';
import { linkSourceToGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { formatLicense, formatWithDescription, sourceToDisplay } from '../../../libs/pages/renderhelpers';
import { TABLE_CUSTOM_STYLES } from '../../../libs/utils/DataTableConstants';

type Props = {
    host: HostApi;
    taxonomy: FGS;
};

const linkGall = (g: GallSimple) => {
    return (
        <>
            <Link key={g.id} href={`/gall/${g.id}`}>
                <a>
                    <i>{g.name}</i>
                </a>
            </Link>
            <Edit id={g.id} type="gall" />
        </>
    );
};

const Host = ({ host, taxonomy }: Props): JSX.Element => {
    const source = host ? host.speciessource.find((s) => s.useasdefault !== 0) : undefined;
    const [selectedSource, setSelectedSource] = useState(source);

    const columns = useMemo(
        () => [
            {
                id: 'name',
                selector: (row: GallSimple) => row.name,
                name: 'Gall',
                sortable: true,
                format: linkGall,
            },
        ],
        [],
    );

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    // the galls will not be sorted, so sort them for display
    host.galls.sort((a, b) => a.name.localeCompare(b.name));

    return (
        <Container className="pt-2" fluid>
            <Head>
                <title>{host.name}</title>
                <meta name="description" content={[host.name, ...host.aliases.map((a) => a.name)].join(', ')} />
            </Head>

            <Row>
                {/* The details column */}
                <Col sm={12} md={6} lg={8}>
                    <Row>
                        <Col className="">
                            <h2 className="font-italic">
                                <Link
                                    href={`/id?hostOrTaxon=${encodeURI(
                                        host.name,
                                    )}&type=host&detachable=&alignment=&cells=&color=&locations=&season=&shape=&textures=&walls=&form=&undescribed=false`}
                                >
                                    <a>{host.name}</a>
                                </Link>
                            </h2>
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
                            <p>
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
                                                <a className="font-italic">{`${s.name} (${s.description})`}</a>
                                            </Link>
                                        </span>
                                    )),
                                    O.map((s) => s),
                                    O.getOrElse(constant(<></>)),
                                )}
                                {' | '}
                                <strong>Genus: </strong>
                                <Link key={taxonomy.genus.id} href={`/genus/${taxonomy.genus.id}`}>
                                    <a className="font-italic">
                                        {' '}
                                        {formatWithDescription(taxonomy.genus.name, taxonomy.genus.description)}
                                    </a>
                                </Link>
                            </p>
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
                    <Row>
                        <Col>
                            <strong>Range:</strong>{' '}
                            {host.places.map((p) => (
                                <Link key={p.id} href={`/place/${p.id}`}>
                                    <a>{p.code} </a>
                                </Link>
                            ))}
                        </Col>
                    </Row>
                    <Row>
                        <Col>
                            <SpeciesSynonymy aliases={host.aliases} />
                        </Col>
                    </Row>

                    <Row className="pt-2">
                        <Col>
                            <DataTable
                                keyField={'id'}
                                data={host.galls}
                                columns={columns}
                                striped
                                noHeader
                                fixedHeader
                                responsive={false}
                                defaultSortFieldId="name"
                                customStyles={TABLE_CUSTOM_STYLES}
                                pagination={true}
                            />
                        </Col>
                    </Row>
                </Col>

                <Col sm={12} md={6} lg={4} className="border rounded p-1">
                    <Images sp={host} type="host" />
                </Col>
            </Row>
            <hr />
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
                        data={host.speciessource}
                        defaultSelection={selectedSource?.source}
                        onSelectionChange={(s) => setSelectedSource(host.speciessource.find((spso) => spso.source_id == s?.id))}
                    />
                    <hr />
                    <Row>
                        <Col className="align-self-center">
                            <strong>See Also:</strong>
                        </Col>
                    </Row>
                    <SeeAlso name={host.name} />
                </Col>
            </Row>
        </Container>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    const h = await getStaticPropsWithContext(context, hostById, 'host');
    const host = h[0];
    const sources = host ? await linkSourceToGlossary(host.speciessource) : null;
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
