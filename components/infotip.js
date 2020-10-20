import { OverlayTrigger, Badge, Tooltip } from 'react-bootstrap';

const InfoTip = ({text}) => {
    return (
        <OverlayTrigger 
            placement="top"
            overlay={
                <Tooltip>{text}</Tooltip>
            }
        >
            <sup><Badge pill variant="info" className="m-1">i</Badge></sup>
        </OverlayTrigger>
    )
};
  
export default InfoTip;