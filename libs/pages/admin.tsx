import Head from 'next/head';
import React from 'react';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import { Toaster } from 'react-hot-toast';
import Auth from '../../components/auth';
import EditName, { RenameEvent } from '../../components/editname';
import { DeleteResult } from '../api/apitypes';
import { WithID } from '../utils/types';

export type AdminProps<T> = {
    type: string;
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
    setDeleteResults: (dr: DeleteResult) => void;
    selected: T | undefined;
};

const validLinkableTypes = ['Gall', 'Host', 'Family', 'Section', 'Source'];

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
const Admin = <T extends WithID>(props: AdminProps<T>): JSX.Element => {
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

                {props.children}

                <Row hidden={!props.deleteResults}>
                    <Col>{`Deleted ${props.deleteResults?.name}.`}</Col>
                </Row>
                {props.selected != undefined && validLinkableTypes.includes(props.type) && (
                    <p className="pl-4">
                        <a href={`/${props.type.toLowerCase()}/${props.selected.id}`}>{`Link to ${props.type}`}</a>
                    </p>
                )}
            </>
        </Auth>
    );
};

export default Admin;
