import Head from 'next/head';
import React from 'react';
import { Alert, Col, Nav, Navbar, Row } from 'react-bootstrap';
import { Toaster } from 'react-hot-toast';
import Auth from '../../components/auth';
import EditName, { RenameEvent } from '../../components/editname';
import { DeleteResult, GallTaxon, HostTaxon } from '../api/apitypes';
import { WithID } from '../utils/types';

export type AdminProps<T> = {
    type: 'Family' | 'Gall' | 'Gallhost' | 'Glossary' | 'Host' | 'Images' | 'Source' | 'Speciessource' | 'Section';
    keyField: string;
    children: JSX.Element;
    editName?: {
        getDefault: () => string | undefined;
        renameCallback: (e: RenameEvent) => void;
    };
    showModal?: boolean;
    setShowModal?: (show: boolean) => void;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults?: (dr: DeleteResult) => void;
    selected: T | undefined;
};

type AdminType = WithID & { taxoncode?: string | null };

/**
 * The Admin component handles the following things that are independent of what data is being manipulated:
 * 1) Authentication - only admins can access an admin screen
 * 2) Toasts
 * 3) Ability to Edit the "name" field. Does not have to be called name.
 * 4) Displaying errors.
 *
 * @param props @see AdminProps
 * @returns
 */
const Admin = <T extends AdminType>(props: AdminProps<T>): JSX.Element => {
    const params = (key: string, destination: string) => {
        const allowed = () => {
            if (
                ['Speciessource', 'Images', 'Host'].includes(props.type) &&
                ['Speciessource', 'Images', 'Host'].includes(destination) &&
                props.selected?.taxoncode === HostTaxon
            ) {
                return true;
            } else if (
                ['Speciessource', 'Gallhost', 'Images', 'Gall'].includes(props.type) &&
                ['Speciessource', 'Gallhost', 'Images', 'Gall'].includes(destination) &&
                props.selected?.taxoncode === GallTaxon
            ) {
                return true;
            } else {
                return false;
            }
        };

        if (props.selected?.id && allowed()) {
            return `?${key}=${props.selected.id}`;
        } else {
            return '';
        }
    };

    const link = () => {
        switch (props.type) {
            case 'Gall':
            case 'Gallhost':
                return `/gall/${props.selected?.id}`;
            case 'Host':
                return `/host/${props.selected?.id}`;
            case 'Section':
                return `/section/${props.selected?.id}`;
            case 'Family':
                return `/family/${props.selected?.id}`;
            case 'Glossary':
                return `/glossary/${props.selected?.id}`;
            case 'Source':
                return `/source/${props.selected?.id}`;
            case 'Images':
            case 'Speciessource':
                if (props.selected?.taxoncode == GallTaxon) {
                    return `/gall/${props.selected?.id}`;
                } else {
                    return `/host/${props.selected?.id}`;
                }
        }
    };
    return (
        <Auth>
            <>
                <Head>
                    <title>{`Add/ Edit ${props.type}s`}</title>
                </Head>

                <Toaster />

                {props.editName != undefined && props.setShowModal != undefined && props.showModal != undefined && (
                    <EditName
                        type={props.type}
                        keyField={props.keyField}
                        defaultValue={props.editName.getDefault()}
                        showModal={props.showModal}
                        setShowModal={props.setShowModal}
                        renameCallback={props.editName.renameCallback}
                    />
                )}

                {props.error.length > 0 && (
                    <Alert variant="danger" onClose={() => props.setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{props.error}</p>
                    </Alert>
                )}

                <Navbar bg="" variant="light">
                    <Nav.Link
                        // disabled={!validLinkableTypes.includes(props.type) || !props.selected}
                        disabled={!props.selected}
                        href={link()}
                        // validLinkableTypes.includes(props.type) || !props.selected
                        //     ? `/${props.type.toLowerCase()}/${props.selected?.id}`
                        //     : ''
                        // }
                    >
                        🔗
                    </Nav.Link>
                    <Nav variant="tabs" defaultActiveKey={props.type}>
                        <Nav.Link eventKey="Gall" href={`./gall${params('id', 'Gall')}`}>{`Galls`}</Nav.Link>
                        <Nav.Link eventKey="Host" href={`./host${params('id', 'Host')}`}>{`Hosts`}</Nav.Link>
                        <Nav.Link eventKey="Images" href={`./images${params('speciesid', 'Images')}`}>{`Images`}</Nav.Link>
                        <Nav.Link
                            eventKey="Speciessource"
                            href={`./speciessource${params('id', 'Speciessource')}`}
                        >{`Source Map`}</Nav.Link>
                        <Nav.Link eventKey="Gallhost" href={`./gallhost${params('id', 'Gall')}`}>{`Gall Hosts`}</Nav.Link>
                        <Nav.Link eventKey="Source" href={`./source`}>{`Sources`}</Nav.Link>
                        <Nav.Link eventKey="Family" href={`./family`}>{`Families`}</Nav.Link>
                        <Nav.Link eventKey="Section" href={`./section`}>{`Sections`}</Nav.Link>
                        <Nav.Link eventKey="Glossary" href={`./glossary`}>{`Glossary`}</Nav.Link>
                    </Nav>
                </Navbar>

                {props.children}

                <Row hidden={!props.deleteResults}>
                    <Col>{`Deleted ${props.deleteResults?.name}.`}</Col>
                </Row>
            </>
        </Auth>
    );
};

export default Admin;
