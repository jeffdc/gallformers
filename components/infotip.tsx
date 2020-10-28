import { OverlayTrigger, Badge, Tooltip } from 'react-bootstrap';

type Props = {
    id: string,
    text: string
}
const InfoTip = ({id, text}: Props): JSX.Element => {
    return (
        <OverlayTrigger 
            placement="top"
            overlay={
                <Tooltip id={id}>{text}</Tooltip>
            }
        >
            <sup><Badge pill variant="info" className="m-1">i</Badge></sup>
        </OverlayTrigger>
    )
};
  
export default InfoTip;