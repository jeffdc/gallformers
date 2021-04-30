import { OverlayTrigger, Badge, Tooltip } from 'react-bootstrap';

type Props = {
    id: string;
    text: string;
    tip?: string;
};
const InfoTip = ({ id, text, tip }: Props): JSX.Element => {
    return (
        <OverlayTrigger
            placement="top"
            overlay={
                <Tooltip id={id} className="info-tip">
                    <p>{text}</p>
                </Tooltip>
            }
        >
            <sup>
                <Badge pill variant="info" className="m-1">
                    {tip ? tip : 'i'}
                </Badge>
            </sup>
        </OverlayTrigger>
    );
};

export default InfoTip;
