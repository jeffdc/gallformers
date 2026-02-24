# Place Reference — Canonical Map Coverage

Generated from `priv/gallformers.sqlite` place table, cross-referenced against
`build_boundaries.sh` COUNTRIES, STATE_COUNTRIES, and subunit arrays.

## Summary

| Category | Count |
|----------|-------|
| Continents | 8 |
| Countries | 249 |
| States | 268 |
| Provinces | 4,022 |
| Place hierarchy entries | 4,539 |
| Countries with subdivisions | 163 |

## Known Code Mismatches (DB vs Natural Earth)

These DB subdivision codes don't match Natural Earth's `iso_3166_2` values.
The features exist in tiles under different codes — no geometry is missing.

| DB Code | DB Name | NE Code | NE Name | Notes |
|---------|---------|---------|---------|-------|
| CO-DC | Bogota | CO-CUN | Cundinamarca | NE treats Bogota as part of Cundinamarca |
| PE-LMA | Lima Province | PE-LIM | Lima | NE uses PE-LIM for both Lima and Lima Province |

## Countries by Continent

### Africa (60 countries)

| Code | Name | Subdivided |
|------|------|------------|
| DZ | Algeria | yes |
| AO | Angola | yes |
| BJ | Benin | yes |
| BW | Botswana | yes |
| BV | Bouvet Island | no |
| BF | Burkina Faso | yes |
| BI | Burundi | yes |
| CV | Cabo Verde | yes |
| CM | Cameroon | yes |
| CF | Central African Republic | yes |
| TD | Chad | yes |
| KM | Comoros | no |
| CI | Côte d'Ivoire | yes |
| CD | Democratic Republic of the Congo | yes |
| DJ | Djibouti | yes |
| EG | Egypt | yes |
| GQ | Equatorial Guinea | yes |
| ER | Eritrea | yes |
| SZ | Eswatini | yes |
| ET | Ethiopia | yes |
| TF | French Southern Territories | no |
| GA | Gabon | yes |
| GM | Gambia | yes |
| GH | Ghana | yes |
| GN | Guinea | yes |
| GW | Guinea-Bissau | yes |
| KE | Kenya | yes |
| LS | Lesotho | yes |
| LR | Liberia | yes |
| LY | Libya | yes |
| MG | Madagascar | yes |
| MW | Malawi | yes |
| ML | Mali | yes |
| MR | Mauritania | yes |
| MU | Mauritius | yes |
| YT | Mayotte | no |
| MA | Morocco | yes |
| MZ | Mozambique | yes |
| NA | Namibia | yes |
| NE | Niger | yes |
| NG | Nigeria | yes |
| CG | Republic of the Congo | yes |
| RW | Rwanda | yes |
| RE | Réunion | no |
| SH | Saint Helena, Ascension and Tristan da Cunha | no |
| SN | Senegal | yes |
| SC | Seychelles | yes |
| SL | Sierra Leone | yes |
| SO | Somalia | yes |
| ZA | South Africa | yes |
| SS | South Sudan | yes |
| SD | Sudan | yes |
| ST | São Tomé and Príncipe | no |
| TZ | Tanzania | yes |
| TG | Togo | yes |
| TN | Tunisia | yes |
| UG | Uganda | yes |
| EH | Western Sahara | no |
| ZM | Zambia | yes |
| ZW | Zimbabwe | yes |

### Asia (51 countries)

| Code | Name | Subdivided |
|------|------|------------|
| AF | Afghanistan | yes |
| AM | Armenia | yes |
| AZ | Azerbaijan | yes |
| BH | Bahrain | yes |
| BD | Bangladesh | yes |
| BT | Bhutan | yes |
| IO | British Indian Ocean Territory | no |
| BN | Brunei | yes |
| KH | Cambodia | yes |
| CN | China | yes |
| CY | Cyprus | yes |
| GE | Georgia | yes |
| HK | Hong Kong | no |
| IN | India | yes |
| ID | Indonesia | yes |
| IR | Iran | yes |
| IQ | Iraq | yes |
| IL | Israel | yes |
| JP | Japan | yes |
| JO | Jordan | yes |
| KZ | Kazakhstan | yes |
| KW | Kuwait | yes |
| KG | Kyrgyzstan | yes |
| LA | Laos | yes |
| LB | Lebanon | yes |
| MO | Macau | no |
| MY | Malaysia | yes |
| MV | Maldives | yes |
| MN | Mongolia | yes |
| MM | Myanmar | yes |
| NP | Nepal | yes |
| KP | North Korea | yes |
| OM | Oman | yes |
| PK | Pakistan | yes |
| PS | Palestine | no |
| PH | Philippines | yes |
| QA | Qatar | yes |
| SA | Saudi Arabia | yes |
| SG | Singapore | yes |
| KR | South Korea | yes |
| LK | Sri Lanka | yes |
| SY | Syria | yes |
| TW | Taiwan | yes |
| TJ | Tajikistan | yes |
| TH | Thailand | yes |
| TL | Timor-Leste | yes |
| TR | Turkey | yes |
| TM | Turkmenistan | yes |
| AE | United Arab Emirates | yes |
| UZ | Uzbekistan | yes |
| VN | Vietnam | yes |
| YE | Yemen | yes |

### Caribbean (27 countries/territories)

| Code | Name | Subdivided |
|------|------|------------|
| AI | Anguilla | no |
| AG | Antigua and Barbuda | yes |
| AW | Aruba | no |
| BS | Bahamas | yes |
| BB | Barbados | yes |
| BM | Bermuda | yes |
| BQ | Bonaire, Sint Eustatius and Saba | no |
| VG | British Virgin Islands | no |
| KY | Cayman Islands | no |
| CU | Cuba | yes |
| CW | Curaçao | no |
| DM | Dominica | yes |
| DO | Dominican Republic | yes |
| GD | Grenada | yes |
| GP | Guadeloupe | no |
| HT | Haiti | yes |
| JM | Jamaica | yes |
| MQ | Martinique | no |
| MS | Montserrat | no |
| PR | Puerto Rico | no |
| BL | Saint Barthélemy | no |
| KN | Saint Kitts and Nevis | yes |
| LC | Saint Lucia | yes |
| MF | Saint Martin | no |
| VC | Saint Vincent and the Grenadines | yes |
| SX | Sint Maarten | no |
| TT | Trinidad and Tobago | yes |
| TC | Turks and Caicos Islands | no |
| VI | United States Virgin Islands | no |

### Central America (7 countries)

| Code | Name | Subdivided |
|------|------|------------|
| BZ | Belize | yes |
| CR | Costa Rica | yes |
| SV | El Salvador | yes |
| GT | Guatemala | yes |
| HN | Honduras | yes |
| NI | Nicaragua | yes |
| PA | Panama | yes |

### Europe (47 countries/territories)

| Code | Name | Subdivided |
|------|------|------------|
| AL | Albania | yes |
| AD | Andorra | yes |
| AT | Austria | yes |
| BY | Belarus | yes |
| BE | Belgium | yes |
| BA | Bosnia and Herzegovina | yes |
| BG | Bulgaria | yes |
| HR | Croatia | yes |
| CZ | Czechia | yes |
| DK | Denmark | yes |
| EE | Estonia | yes |
| FO | Faroe Islands | no |
| FI | Finland | yes |
| FR | France | yes |
| DE | Germany | yes |
| GI | Gibraltar | no |
| GR | Greece | yes |
| GG | Guernsey | no |
| HU | Hungary | yes |
| IS | Iceland | yes |
| IE | Ireland | yes |
| IM | Isle of Man | no |
| IT | Italy | yes |
| JE | Jersey | no |
| XK | Kosovo | no |
| LV | Latvia | yes |
| LI | Liechtenstein | yes |
| LT | Lithuania | yes |
| LU | Luxembourg | no |
| MT | Malta | yes |
| MD | Moldova | yes |
| MC | Monaco | no |
| ME | Montenegro | yes |
| NL | Netherlands | yes |
| MK | North Macedonia | yes |
| NO | Norway | yes |
| PL | Poland | yes |
| PT | Portugal | yes |
| RO | Romania | yes |
| RU | Russia | yes |
| SM | San Marino | yes |
| RS | Serbia | yes |
| SK | Slovakia | yes |
| SI | Slovenia | yes |
| ES | Spain | yes |
| SJ | Svalbard and Jan Mayen | no |
| SE | Sweden | yes |
| CH | Switzerland | yes |
| UA | Ukraine | yes |
| GB | United Kingdom | yes |
| VA | Vatican City | no |
| AX | Åland Islands | no |

### North America (5 countries/territories)

| Code | Name | Subdivided |
|------|------|------------|
| CA | Canada | yes |
| GL | Greenland | yes |
| MX | Mexico | yes |
| PM | Saint Pierre and Miquelon | no |
| US | United States | yes |

### Oceania (27 countries/territories)

| Code | Name | Subdivided |
|------|------|------------|
| AS | American Samoa | no |
| AU | Australia | yes |
| CX | Christmas Island | no |
| CC | Cocos (Keeling) Islands | no |
| CK | Cook Islands | no |
| FJ | Fiji | yes |
| PF | French Polynesia | no |
| GU | Guam | no |
| HM | Heard Island and McDonald Islands | no |
| KI | Kiribati | no |
| MH | Marshall Islands | no |
| FM | Micronesia | yes |
| NR | Nauru | yes |
| NC | New Caledonia | no |
| NZ | New Zealand | yes |
| NU | Niue | no |
| NF | Norfolk Island | no |
| MP | Northern Mariana Islands | no |
| PW | Palau | yes |
| PG | Papua New Guinea | yes |
| PN | Pitcairn Islands | no |
| WS | Samoa | yes |
| SB | Solomon Islands | yes |
| TK | Tokelau | no |
| TO | Tonga | yes |
| TV | Tuvalu | no |
| UM | United States Minor Outlying Islands | yes |
| VU | Vanuatu | yes |
| WF | Wallis and Futuna | no |

### South America (14 countries/territories)

| Code | Name | Subdivided |
|------|------|------------|
| AR | Argentina | yes |
| BO | Bolivia | yes |
| BR | Brazil | yes |
| CL | Chile | yes |
| CO | Colombia | yes |
| EC | Ecuador | yes |
| FK | Falkland Islands | no |
| GF | French Guiana | no |
| GY | Guyana | yes |
| PY | Paraguay | yes |
| PE | Peru | yes |
| GS | South Georgia and the South Sandwich Islands | no |
| SR | Suriname | yes |
| UY | Uruguay | yes |
| VE | Venezuela | yes |
