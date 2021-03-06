import * as A from 'fp-ts/lib/Array';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { GetStaticPaths, GetStaticProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { MouseEvent, useState } from 'react';
import { Button, Col, Container, ListGroup, Row } from 'react-bootstrap';
import Edit from '../../../components/edit';
import Images from '../../../components/images';
import InfoTip from '../../../components/infotip';
import { DetachableBoth, GallApi, GallHost, SourceApi, SpeciesSourceApi } from '../../../libs/api/apitypes';
import { allGallIds, gallById } from '../../../libs/db/gall';
import { linkTextFromGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { defaultSource, renderCommonNames } from '../../../libs/pages/renderhelpers';
import { deserialize, serialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, errorThrow, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    species: GallApi;
};

type SortPropertyOption = {
    property: keyof Pick<SourceApi, 'pubyear' | 'citation'>;
    propertyText: string;
};

const sourceSortPropertyOptions: SortPropertyOption[] = [
    {
        property: 'pubyear',
        propertyText: 'Year',
    },
    {
        property: 'citation',
        propertyText: 'Author',
    },
];

type SortOrderOption = 1 | -1;

const ascText = '▲';
const descText = '▼';

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

const Gall = ({ species }: Props): JSX.Element => {
    const [selectedSource, setSelectedSource] = useState(defaultSource(species?.speciessource));
    const [sourceList, setSourceList] = useState({ data: species?.speciessource, sortIndex: 0, sortOrder: -1 });

    const router = useRouter();
    // If the page is not yet generated, this will be displayed initially until getStaticProps() finishes running
    if (router.isFallback) {
        return <div>Loading...</div>;
    }

    // Initially sort the list of sources by most recent year.
    species.speciessource.sort((a, b) => -a.source.pubyear.localeCompare(b.source.pubyear));

    // the hosts will not be sorted, so sort them for display
    species.hosts.sort((a, b) => a.name.localeCompare(b.name));
    const hostLinker = hostAsLink(species.hosts.length);

    const changeDescription = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        const id = e.currentTarget.id;
        const s = species.speciessource.find((s) => s.source_id.toString() === id);
        setSelectedSource(s);
    };

    const sortSourceList = () => {
        const newSortIndex = (sourceList.sortIndex + 1) % sourceSortPropertyOptions.length;
        const sortProperty = sourceSortPropertyOptions[newSortIndex].property;

        const newData = [...sourceList.data];
        newData.sort((a, b) => sourceList.sortOrder * a.source[sortProperty].localeCompare(b.source[sortProperty]));

        setSourceList({ data: newData, sortIndex: newSortIndex, sortOrder: sourceList.sortOrder });
    };

    const toggleAscDesc = () => {
        const newSortOrder: SortOrderOption = sourceList.sortOrder == -1 ? 1 : -1; // multiplication does not work on constrained type.
        const sortProperty = sourceSortPropertyOptions[sourceList.sortIndex].property;

        const newData = [...sourceList.data];
        newData.sort((a, b) => newSortOrder * a.source[sortProperty].localeCompare(b.source[sortProperty]));

        setSourceList({ data: newData, sortIndex: sourceList.sortIndex, sortOrder: newSortOrder });
    };

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
                    <Col>
                        <Row className="">
                            <Edit id={species.id} type="gall" />
                            <Col>
                                <h2>{species.name}</h2>
                                {renderCommonNames(species.commonnames)}
                                <p className="font-italic">
                                    <strong>Family:</strong>
                                    <Link key={species.family.id} href={`/family/${species.family.id}`}>
                                        <a> {species.family.name}</a>
                                    </Link>
                                </p>
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <Edit id={species.id} type="gallhost" />
                                <strong>Hosts:</strong> {species.hosts.map(hostLinker)}
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
                        </Row>
                    </Col>
                    <Col xs={4} className="border rounded p-1 mx-auto">
                        <Images species={species} type="gall" />
                    </Col>
                </Row>

                <Row>
                    <Col id="description" className="lead p-3">
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
                        <strong>Further Information:</strong>
                    </Col>
                    <Col xs={2}>
                        <Button variant="outline-secondary" className="btn-sm" onClick={sortSourceList}>
                            {sourceSortPropertyOptions[sourceList.sortIndex].propertyText}
                        </Button>
                        <Button variant="outline-secondary" className="btn-sm" onClick={toggleAscDesc}>
                            {sourceList.sortOrder == -1 ? descText : ascText}
                        </Button>
                    </Col>
                </Row>
                <Row>
                    <Col>
                        <ListGroup variant="flush" defaultActiveKey={selectedSource?.source_id}>
                            {sourceList.data.map((speciessource) => (
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

    const updateSpeciesSource = (d: string, source: SpeciesSourceApi): SpeciesSourceApi => {
        return {
            ...source,
            description: d,
        };
    };

    // eslint-disable-next-line prettier/prettier
    const sources = await pipe(
        gall.speciessource,
        A.map((s) => linkTextFromGlossary(O.fromNullable(s.description))),
        A.map(TE.map(serialize)),
        TE.sequenceArray,
        // sequence makes the array readonly, the rest of the fp-ts API does not use readonly, ...sigh.
        TE.map((d) => A.zipWith(d as string[], gall.speciessource, updateSpeciesSource)),
        TE.getOrElse(errorThrow),
    )();

    return {
        props: {
            species: { ...gall, speciessource: sources },
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => getStaticPathsFromIds(allGallIds);

export default Gall;
