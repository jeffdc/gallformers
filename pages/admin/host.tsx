import { yupResolver } from '@hookform/resolvers/yup';
import { abundance, family } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import {
    AbundanceApi,
    DeleteResult,
    EmptyAbundance,
    EmptyFamily,
    FamilyApi,
    HOST_FAMILY_TYPES,
    SpeciesApi,
    SpeciesUpsertFields,
} from '../../libs/api/apitypes';
import { allFamilies } from '../../libs/db/family';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    hs: SpeciesApi[];
    families: family[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const Schema = yup.object().shape({
    value: yup
        .array()
        .of(
            yup.object({
                name: yup
                    .string()
                    .matches(/([A-Z][a-z]+ [a-z]+$)/)
                    .required(),
            }),
        )
        .min(1)
        .max(1),
    family: yup.mixed().required(),
});

export type FormFields = AdminFormFields<SpeciesApi> & {
    genus: string;
    family: FamilyApi[];
    abundance: AbundanceApi[];
    commonnames: string;
    synonyms: string;
};

export const testables = {
    extractGenus: extractGenus,
    Schema: Schema,
};

const Host = ({ hs, families, abundances }: Props): JSX.Element => {
    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();
    const [hosts, setHosts] = useState(hs);

    const { register, handleSubmit, setValue, errors, control, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const { doDeleteOrUpsert } = useAPIs<SpeciesApi, SpeciesUpsertFields>('name', '../api/host/', '../api/host/upsert');

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setHosts(hosts.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        const convertFormFieldsToUpsert = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => ({
            abundance: fields.abundance[0].abundance,
            commonnames: fields.commonnames,
            family: fields.family[0].name,
            id: id,
            name: name,
            synonyms: fields.synonyms,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert);
        reset();
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Host</h4>
                <p>
                    This is for all of the details about a Host. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>.
                </p>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <ControlledTypeahead
                            control={control}
                            name="value"
                            onChangeWithNew={(e, isNew) => {
                                setExisting(!isNew);
                                if (isNew || !e[0]) {
                                    setValue('genus', extractGenus(e[0] ? e[0].name : ''));
                                    setValue('family', [EmptyFamily]);
                                    setValue('abundance', [EmptyAbundance]);
                                    setValue('commonnames', '');
                                    setValue('synonyms', '');
                                } else {
                                    const host: SpeciesApi = e[0];
                                    setValue('family', [host.family]);
                                    setValue('abundance', [pipe(host.abundance, O.getOrElse(constant(EmptyAbundance)))]);
                                    setValue('commonnames', pipe(host.commonnames, O.getOrElse(constant(''))));
                                    setValue('synonyms', pipe(host.synonyms, O.getOrElse(constant(''))));
                                }
                            }}
                            onBlurT={(e) => {
                                if (!errors.value) {
                                    setValue('genus', extractGenus(e.target.value));
                                }
                            }}
                            placeholder="Name"
                            options={hosts}
                            labelKey="name"
                            clearButton
                            isInvalid={!!errors.value}
                            newSelectionPrefix="Add a new Host: "
                            allowNew={true}
                        />
                        {errors.value && (
                            <span className="text-danger">
                                Name is required and must be in standard binomial form, e.g., Gallus gallus
                            </span>
                        )}
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={register} />
                    </Col>
                    <Col>
                        Family:
                        <ControlledTypeahead
                            control={control}
                            name="family"
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                        />
                        {errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <ControlledTypeahead
                            control={control}
                            name="abundance"
                            placeholder=""
                            options={abundances}
                            labelKey="abundance"
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Common Names (comma-delimited):
                        <input
                            type="text"
                            placeholder="Common Names"
                            name="commonnames"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Synonyms (comma-delimited):
                        <input type="text" placeholder="Synonyms" name="synonyms" className="form-control" ref={register} />
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!existing}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-check-input" ref={register} />
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                </Row>
                <Row hidden={!deleteResults}>
                    <Col>{`Deleted ${deleteResults?.name}.`}</Col>
                </Row>
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            hs: await mightFailWithArray<SpeciesApi>()(allHosts()),
            families: await mightFailWithArray<FamilyApi>()(allFamilies(HOST_FAMILY_TYPES)),
            abundances: await mightFailWithArray<AbundanceApi>()(abundances()),
        },
    };
};

export default Host;
