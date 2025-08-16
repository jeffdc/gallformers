import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { ImageApi } from '../libs/api/apitypes';

type Props = {
    colCount: 1 | 2 | 3 | 4 | 6 | 12;
    images: ImageApi[];
    selected: Set<number>;
    setSelected: (images: Set<number>) => void;
};

const ImageGrid: React.FC<Props> = ({ colCount, images, selected, setSelected }): JSX.Element => {
    const rows = images.reduce((acc, image, idx) => {
        if (idx % colCount == 0) {
            acc.push(new Array<ImageApi>());
        }
        acc[acc.length - 1].push(image);
        return acc;
    }, new Array<Array<ImageApi>>());

    const selectImage = (e: React.MouseEvent<HTMLImageElement, MouseEvent>) => {
        const id = parseInt(e.currentTarget.id);

        if (selected.has(id)) {
            selected.delete(id);
            e.currentTarget.className = '';
        } else {
            selected.add(id);
            e.currentTarget.className = 'img-thumbnail shadow-lg bg-primary';
        }
        setSelected(selected);
    };

    return (
        <>
            {rows.map((cols, idx) => (
                <Row key={`row-${idx}`}>
                    {cols.map((img) => (
                        <Col key={img.id} xs={12 / colCount}>
                            <img id={img.id.toString()} key={img.id} src={img.small} width="100" onClick={selectImage} />
                        </Col>
                    ))}
                </Row>
            ))}
        </>
    );
};

export default ImageGrid;
