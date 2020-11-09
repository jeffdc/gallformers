import { gall, PrismaClient, species } from '@prisma/client';
import { GetServerSideProps } from 'next';

type Props = species & {
    galls: gall;
};

const Gall = ({ galls }: Props): JSX.Element => {
    return (
        <>
            <p>Edit Gall</p>
            <p>{JSON.stringify(galls)}</p>
        </>
    );
};

export const getServerSideProps: GetServerSideProps = async (context) => {
    const db = new PrismaClient();
    const galls = db.species.findMany({
        include: {
            gall: true,
        },
        where: {
            gall: {},
        },
    });
    return {
        props: {
            galls: galls,
        },
    };
};

export default Gall;
