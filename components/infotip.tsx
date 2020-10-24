import { OverlayTrigger, Badge, Tooltip } from 'react-bootstrap';

const InfoTip = ({id, text}) => {
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