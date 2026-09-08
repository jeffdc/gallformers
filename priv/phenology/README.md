# Seasonal landmark reference

`seasonal_landmarks.csv` is the fixed, species-independent latitude reference
used by `Gallformers.Phenology.SeasonalClock`. It is compiled into the module;
serving predictions requires neither climate downloads nor an R/Python process.

## Provenance

Generated in the September 2026 phenology pilot by
`benchmark_seasonal_onset.R` and `seasonal_landmark_clock.R` in
[Megachile/Phenology](https://github.com/Megachile/Phenology). Input: WorldClim 2.1
monthly mean-temperature normals, sampled at one-degree longitude intervals
from 100°W to 70°W and averaged over available land samples at each quarter-degree
latitude from 25°N through 55°N. The monthly series is interpolated periodically
to daily temperatures. Spring and autumn columns are the dates at which 10% and
90% of annual positive temperature exposure above 5°C have accumulated.
`warm_days` is their difference. These are thermal landmarks, not measurements
of host budbreak or leaf senescence.

## Calculation and scope

The warm interval maps to 0–182.5 clock units; autumn through the following spring
maps to 182.5–365. Both segments are linear, continuous, monotone and periodic.
Latitude interpolation is linear between adjacent grid rows. Inversion supplies
both the chart contours and the displayed dates. Prediction dates use a fixed non-leap year;
February 29 maps to February 28.

The prediction layer pools selected species within generation. It collapses
replicate species/date/0.1°-locality records and gives each occupied 1° geographic
cell equal total weight. A weighted circular mean centers the year, keeping
December–January seasons together. Fresh-gall onset uses the earliest developing
record on that centered, latitude-normalized clock, not a percentile or the
duration of developing galls. Its single line/date links to the anchor record
where a source URL is available. Query-order-independent deduplication makes that
anchor reproducible. This is an earliest **recorded** onset estimate: the input
has no separate verified-fresh flag, and an early mislabel can move the line.
It is not proof of the true first induction date or a confidence bound. Curate
the upstream stage label to correct it; there are no per-species overrides.
The circular centering still assumes a coherent season, not year-round or
several independent developing phases.

### Observation selection

The explorer's Seasonal landmark selection replaces the legacy season-index
lens. A reference date and latitude define a calendar-day window (±0–183 days);
its two clock coordinates are transferred across 25–55°N. The browser receives
the exact bundled reference through the Phenology context API. It uses matching
forward/inverse arithmetic, not another climate artifact or imported `seasind`.
The clipped selection band wraps across the new year without shading unrelated
dates between its two visible pieces.

This is a display-only lens: table, species list, selected count and CSV agree,
while prediction inputs and plotted observations remain unchanged. The server
recomputes CSV membership from reference inputs. Invalid or incomplete landmark
inputs select nothing, show a correction message and return HTTP 400 on export;
records outside the reference latitude domain cannot be selected by this mode.
Clear selection returns to click-and-drag mode.

Selection retains the existing plotted/stored DOY convention, including day 366
in leap years. It does not rewrite source dates or the prediction layer's
non-leap normalization. This existing calendar distinction can produce one-day
differences between a leap-year point and a normalized prediction. The legacy
`seasind` database field remains import provenance, not selection input.

### Other events and limitations

Emergence pools maturing and Free-living phases (not
perimature or enclosed Adult annotations). Viable collections require explicit
`viability == "viable"`, regardless of phenophase. Those events show q25–q75,
with q10–q90 and the median as context. Display filters never restrict event input.

These are descriptive fallback estimates, not confidence intervals, physiological
thresholds or a mechanistic lifecycle model. Sparse evidence and extrapolation
are labeled in plain language, without exposing geographic-cell counts. Fewer
than five deduplicated records trigger a few-records warning. Outside the
observed latitude range, the requested and recorded latitudes are displayed as
an explicit extrapolation warning. Within that range, a span under two degrees
triggers a limited-latitude-coverage warning. These are disclosure heuristics,
not calibrated confidence scores; broad latitude coverage alone does not imply
good sampling throughout the range or longitude coverage.
A single site can supply event thresholds but does not validate the
latitude-transfer relationship. Multimodal cohorts may not be well summarized by
one window. The reference is eastern/central North American, not local weather;
altitude, aspect, host and annual variation are not modeled. Do not use its
latitude coverage as a claim of geographic validation elsewhere.

No automatic imports, taxonomic pairing, regional climate model, or perimature
review-queue heuristics are part of this application implementation.
