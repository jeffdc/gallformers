import React, { useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Option } from 'react-bootstrap-typeahead/types/types';

type Props<T> = {
    size?: 'sm' | 'lg' | 'xl';
    title: string;
    data: T[];
    toLabel: string | ((t: T) => string);
    show: boolean;
    onClose: (t: T | undefined) => void;
    placeholder?: string;
};

const Picker = <T extends Option>({ size, title, data, toLabel, show, onClose, placeholder }: Props<T>): JSX.Element => {
    const [selected, setSelected] = useState<T | undefined>(undefined);

    const done = () => {
        onClose(selected);
        setSelected(undefined);
    };

    return (
        <Modal size={size} show={show} onHide={() => done()}>
            <Modal.Header id="new-dialog-title" closeButton>
                <Modal.Title>{title}</Modal.Title>
            </Modal.Header>
            <Modal.Body>
                <Typeahead
                    id="select-data"
                    options={data}
                    labelKey={(o: Option) => (typeof toLabel === 'string' ? toLabel : toLabel(o as T))}
                    onChange={(s) => setSelected(s[0] as T)}
                    selected={selected ? [selected] : []}
                    placeholder={placeholder}
                    clearButton
                />
            </Modal.Body>
            <Modal.Footer>
                <div className="d-flex justify-content-end">
                    <Row>
                        <Col xs={4}>
                            <Button variant="primary" onClick={done}>
                                Done
                            </Button>
                        </Col>
                    </Row>
                </div>
            </Modal.Footer>
        </Modal>
    );
};

export default Picker;
