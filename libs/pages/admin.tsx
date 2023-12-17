import { useSession } from 'next-auth/react';
import Head from 'next/head';
import { Alert, Col, Nav, Navbar, Row } from 'react-bootstrap';
import { Toaster } from 'react-hot-toast';
import Auth, { superAdmins } from '../../components/auth';
import EditName, { RenameEvent } from '../../components/editname';
import { DeleteResult } from '../api/apitypes';
import { WithID } from '../utils/types';
import { TaxonCodeValues } from '../api/apitypes';

export type AdminTypes =
    | 'Taxonomy'
    | 'Section'
    | 'Gall'
    | 'Gallhost'
    | 'Glossary'
    | 'Host'
    | 'Images'
    | 'Source'
    | 'Speciessource'
    | 'Place'
    | 'FilterTerms';

export type AdminProps<T> = {
    type: AdminTypes;
    keyField: string;
    children: JSX.Element;
    editName?: {
        getDefault: () => string | undefined;
        renameCallback: (e: RenameEvent) => void;
        nameExistsCallback: (name: string) => Promise<boolean>;
    };
    showModal?: boolean;
    setShowModal?: (show: boolean) => void;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults?: (dr: DeleteResult) => void;
    selected: T | undefined;
    superAdmin?: boolean;
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
                props.selected?.taxoncode === TaxonCodeValues.PLANT
            ) {
                return true;
            } else if (
                ['Speciessource', 'Gallhost', 'Images', 'Gall'].includes(props.type) &&
                ['Speciessource', 'Gallhost', 'Images', 'Gall'].includes(destination) &&
                props.selected?.taxoncode === TaxonCodeValues.GALL
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
            case 'Taxonomy':
                return `/family/${props.selected?.id}`;
            case 'Glossary':
                return `/glossary/${props.selected?.id}`;
            case 'Source':
                return `/source/${props.selected?.id}`;
            case 'Images':
            case 'Speciessource':
                if (props.selected?.taxoncode == TaxonCodeValues.GALL) {
                    return `/gall/${props.selected?.id}`;
                } else {
                    return `/host/${props.selected?.id}`;
                }
            case 'Place':
                return `/place/${props.selected?.id}`;
        }
    };

    const session = useSession();
    const isSuperAdmin = session?.data?.user?.name && superAdmins.includes(session.data.user.name);

    return (
        <Auth superAdmin={!!props.superAdmin}>
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
                        nameExistsCallback={props.editName.nameExistsCallback}
                    />
                )}

                {props.error.length > 0 && (
                    <Alert variant="danger" onClose={() => props.setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{props.error}</p>
                        <p>
                            If you need to create an issue please do so in{' '}
                            <a href="https://github.com/jeffdc/gallformers/issues/new" target="_blank" rel="noreferrer">
                                Github
                            </a>
                            . Grabbing info from the browser console will help with solving the issue. If you are unsure how to to
                            do that you can find instructions{' '}
                            <a href="https://appuals.com/open-browser-console/" target="_blank" rel="noreferrer">
                                here
                            </a>
                            .
                        </p>
                    </Alert>
                )}

                <Navbar bg="" variant="light">
                    <Nav.Link disabled={!props.selected} href={link()}>
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
                        <Nav.Link eventKey="Taxonomy" href={`./taxonomy`}>{`Taxonomy`}</Nav.Link>
                        <Nav.Link eventKey="Section" href={`./section`}>{`Sections`}</Nav.Link>
                        <Nav.Link eventKey="Glossary" href={`./glossary`}>{`Glossary`}</Nav.Link>
                        {isSuperAdmin && <Nav.Link eventKey="Place" href={`./place`}>{`Place`}</Nav.Link>}
                        {isSuperAdmin && <Nav.Link eventKey="FilterTerms" href={`./filterterms`}>{`Filter Terms`}</Nav.Link>}
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
