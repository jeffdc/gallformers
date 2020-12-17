import * as A from 'fp-ts/lib/Array';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React, { MouseEvent, ReactNode, useState } from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { GallApi, GallHost, SpeciesSourceApi } from '../../../libs/api/apitypes';
import { allGallIds, gallById } from '../../../libs/db/gall';
import { linkTextFromGlossary } from '../../../libs/pages/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { renderCommonNames } from '../../../libs/pages/renderhelpers';
import { deserialize, serialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, errorThrow, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    species: GallApi;
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

const Gall = ({ species }: Props): JSX.Element => {
    // the hosts will not be sorted, so sort them for display
    species.hosts.sort((a, b) => a.name.localeCompare(b.name));
    const hostLinker = hostAsLink(species.hosts.length);

    const source = species.speciessource.find((s) => s.useasdefault !== 0);
    const [selectedSource, setSelectedSource] = useState(source);

    const changeDescription = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        const id = e.currentTarget.id;
        const s = species.speciessource.find((s) => s.source_id.toString() === id);
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
                <img width={170} height={128} className="mr-3" src="/images/gall.jpg" alt={species.name} />
                <Media.Body>
                    <Container className="p-3">
                        <Row>
                            <Col>
                                <h2>{species.name}</h2>
                                {renderCommonNames(species.commonnames)}
                            </Col>
                            <Col className="text-right font-italic">
                                Family:
                                <Link key={species.family.id} href={`/family/${species.family.id}`}>
                                    <a> {species.family.name}</a>
                                </Link>
                            </Col>
                        </Row>
                        <Row>
                            <Col id="description" className="lead p-3">
                                {
                                    // eslint-disable-next-line prettier/prettier
                                    pipe(
                                        O.fromNullable(selectedSource?.description),
                                        O.flatten,
                                        O.map(deserialize),
                                        O.getOrElse(constant((<></>) as ReactNode)),
                                    )
                                }
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Hosts:</strong> {species.hosts.map(hostLinker)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Detachable:</strong>{' '}
                                {pipe(
                                    species.gall.detachable,
                                    O.fold(constant('unsure'), (a) => (a === 1 ? 'yes' : 'no')),
                                )}
                            </Col>
                            <Col>
                                <strong>Texture:</strong> {species.gall.galltexture.map((t) => t.tex).join(', ')}
                            </Col>
                            <Col>
                                <strong>Color:</strong>{' '}
                                {pipe(
                                    species.gall.color,
                                    O.fold(constant(''), (c) => c.color),
                                )}
                            </Col>
                            <Col>
                                <strong>Alignment:</strong>{' '}
                                {pipe(
                                    species.gall.alignment,
                                    O.fold(constant(''), (a) => a.alignment),
                                )}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Location:</strong> {species.gall.galllocation.map((l) => l.loc).join(', ')}
                            </Col>
                            <Col>
                                <strong>Walls:</strong>{' '}
                                {pipe(
                                    species.gall.walls,
                                    O.fold(constant(''), (a) => a.walls),
                                )}
                            </Col>
                            <Col>
                                <strong>Abdundance:</strong>{' '}
                                {pipe(
                                    species.abundance,
                                    O.fold(constant(''), (a) => a.abundance),
                                )}
                            </Col>
                            <Col>
                                <strong>Shape:</strong>{' '}
                                {pipe(
                                    species.gall.shape,
                                    O.fold(constant(''), (a) => a.shape),
                                )}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Further Information:</strong>
                                <ListGroup variant="flush" defaultActiveKey={selectedSource?.source_id}>
                                    {species.speciessource
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
                </Media.Body>
            </Media>
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
            description: O.of(d),
        };
    };

    // eslint-disable-next-line prettier/prettier
    const sources = await pipe(
        gall.speciessource,
        A.map((s) => linkTextFromGlossary(s.description)),
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
