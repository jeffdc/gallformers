import * as A from 'fp-ts/lib/Array';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React, { MouseEvent, useState } from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { GallApi, GallHost, Source } from '../../../libs/apitypes';
import { allGallIds, gallById } from '../../../libs/db/gall';
import { linkTextFromGlossary } from '../../../libs/glossary';
import { getStaticPathsFromIds, getStaticPropsWithContext } from '../../../libs/pages/nextPageHelpers';
import { deserialize, serialize } from '../../../libs/utils/reactserialize';
import { bugguideUrl, errorThrow, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    species: GallApi;
};

function hostAsLink(h: GallHost) {
    return (
        <Link key={h.id} href={`/host/${h.id}`}>
            <a>{h.name} </a>
        </Link>
    );
}

const Gall = ({ species }: Props): JSX.Element => {
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
                    <Container className="p-3 border">
                        <Row>
                            <Col>
                                <h2>{species.name}</h2>
                                {species.commonnames ? `(${species.commonnames})` : ''}
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
                                {deserialize(selectedSource?.description)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Hosts:</strong> {species.hosts.map(hostAsLink)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Detachable:</strong> {species.gall.detachable == 1 ? 'yes' : 'no'}
                            </Col>
                            <Col>
                                <strong>Texture:</strong> {species.gall.galltexture.map((t) => t.texture?.texture).join(',')}
                            </Col>
                            <Col>
                                <strong>Color:</strong> {species.gall.color?.color}
                            </Col>
                            <Col>
                                <strong>Alignment:</strong> {species.gall.alignment?.alignment}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Location:</strong> {species.gall.galllocation.map((l) => l.location?.location).join(', ')}
                            </Col>
                            <Col>
                                <strong>Walls:</strong> {species.gall.walls?.walls}
                            </Col>
                            <Col>
                                <strong>Abdundance:</strong> {species.abundance?.abundance}
                            </Col>
                            <Col>
                                <strong>Shape:</strong> {species.gall.shape?.shape}
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

    const updateSpeciesSource = (d: string, source: Source): Source => {
        return {
            ...source,
            description: d,
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
