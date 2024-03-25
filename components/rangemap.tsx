import React, { useState } from 'react';
import { ComposableMap, Geographies, Geography, ProjectionConfig, ZoomableGroup } from 'react-simple-maps';
// needed as ReactTooltip does not play nicely with SSR. See: https://github.com/wwayne/react-tooltip/issues/675
// import dynamic from 'next/dynamic';
import { Tooltip } from 'react-tooltip';

// const ReactTooltip = dynamic(() => import('react-tooltip'), {
//     ssr: false,
// });

type Props = {
    range: Set<string>;
};

const projConfig: ProjectionConfig = {
    center: [-4, 48],
    parallels: [29.5, 45.5],
    rotate: [96, 0, 0],
    scale: 750,
};

const RangeMap = ({ range }: Props): JSX.Element => {
    const [tooltipContent, setTooltipContent] = useState('');

    return (
        <>
            <ComposableMap className="border rounded" projection="geoConicEqualArea" projectionConfig={projConfig} data-tip="">
                <ZoomableGroup
                    zoom={1}
                    minZoom={0.5}
                    translateExtent={[
                        [-1000, -1000],
                        [1000, 1000],
                    ]}
                >
                    <Geographies geography="../usa-can-topo.json">
                        {({ geographies }) =>
                            geographies.map((geo) => {
                                const code = geo.properties.postal;
                                return (
                                    <Geography
                                        key={geo.rsmKey}
                                        geography={geo}
                                        stroke={'Black'}
                                        fill={range.has(code) ? 'ForestGreen' : 'White'}
                                        style={{
                                            default: { outline: 'none' },
                                            hover: { outline: 'none' },
                                            pressed: { outline: 'none' },
                                        }}
                                        onMouseEnter={() => setTooltipContent(`${code} - ${geo.properties.name}`)}
                                        onMouseLeave={() => setTooltipContent('')}
                                    />
                                );
                            })
                        }
                    </Geographies>
                </ZoomableGroup>
            </ComposableMap>
            <Tooltip variant="dark" /*textColor="white"*/>{tooltipContent}</Tooltip>
        </>
    );
};

export default RangeMap;
