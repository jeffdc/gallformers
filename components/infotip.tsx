import { ReactNode } from 'react';
import { OverlayTrigger, Badge, Tooltip } from 'react-bootstrap';

type Props = {
    id: string;
    text?: string;
    children?: ReactNode;
    tip?: string;
};
const InfoTip = ({ id, text, children, tip }: Props): JSX.Element => {
    return (
        <OverlayTrigger
            placement="auto"
            overlay={
                <Tooltip id={id} className="info-tip">
                    {text && <p>{text}</p>}
                    {children && <>{children}</>}
                </Tooltip>
            }
        >
            <sup>
                <Badge pill bg="secondary" className="m-1" style={{ fontFamily: 'monospace' }}>
                    {tip ? tip : 'i'}
                </Badge>
            </sup>
        </OverlayTrigger>
    );
};

export default InfoTip;
