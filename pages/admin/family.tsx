import { yupResolver } from '@hookform/resolvers/yup';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES, DeleteResult, FamilyApi, FamilyUpsertFields } from '../../libs/api/apitypes';
import { allFamilies } from '../../libs/db/family';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';
import { ParsedUrlQuery } from 'querystring';

const Schema = yup.object().shape({
    value: yup.mixed().required(),
    description: yup.string().required(),
});

type Props = {
    id: string;
    fs: FamilyApi[];
};

type FormFields = AdminFormFields<FamilyApi> & Omit<FamilyApi, 'id' | 'name'>;

const Family = ({ id, fs }: Props): JSX.Element => {
    if (!fs) throw new Error(`The input props for families can not be null or undefined.`);
    const [families, setFamilies] = useState(fs);
    const [error, setError] = useState('');
    const [existingId, setExistingId] = useState<number | undefined>(id && id !== '' ? parseInt(id) : undefined);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { register, handleSubmit, errors, control, setValue, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onFamilyChange = useCallback(
        (id: number | undefined) => {
            if (id == undefined) {
                setValue('value', []);
                setValue('description', '');
            } else {
                try {
                    const fam = families.find((f) => f.id === id);
                    if (fam == undefined) {
                        throw new Error(`Somehow we have a family selection that does not exist?! familyid: ${id}`);
                    }

                    setValue('value', [fam]);
                    setValue('description', fam.description);
                } catch (e) {
                    console.error(e);
                }
            }
        },
        [families, setValue],
    );

    useEffect(() => {
        onFamilyChange(existingId);
    }, [existingId, onFamilyChange]);

    const { doDeleteOrUpsert } = useAPIs<FamilyApi, FamilyUpsertFields>('name', '../api/family/', '../api/family/upsert');

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setFamilies(families.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const convertFormFieldsToUpsert = (fields: FormFields, name: string, id: number): FamilyUpsertFields => ({
            ...fields,
            name: name,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e) => setError(`Failed to save changes. ${e}.`));
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Families</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add or Edit a Family</h4>
                    <Row className="form-group">
                        <Col>
                            Name:
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                placeholder="Name"
                                options={families}
                                labelKey="name"
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Family: "
                                allowNew={true}
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        setExistingId(e[0].id);
                                        router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                    }
                                }}
                            />
                            {errors.value && <span className="text-danger">The Name is required.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Description:
                            <select name="description" className="form-control" ref={register}>
                                {genOptions(ALL_FAMILY_TYPES)}
                            </select>
                            {errors.description && <span className="text-danger">You must provide the description.</span>}
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!existingId}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={register} />
                        </Col>
                        <Col xs="8">
                            <em className="text-danger">
                                Caution. If there are any species (galls or hosts) assigned to this Family they too will be
                                deleted.
                            </em>
                        </Col>
                    </Row>
                    <Row className="form-input">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    <Row hidden={!deleteResults}>
                        <Col>{`Deleted ${deleteResults?.name}.`}</Col>☹️
                    </Row>
                </form>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    return {
        props: {
            id: id,
            fs: await mightFailWithArray<FamilyApi>()(allFamilies()),
        },
    };
};
export default Family;
