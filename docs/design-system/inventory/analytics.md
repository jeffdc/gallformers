# Inventory: the analytics page

The behavior contract for the public analytics page (`/analytics`, `AnalyticsLive`, reads in `Gallformers.Analytics`), taken from the code on 2026-11-05 (design-system branch).

## Behaviors

- **Periods:** Today (default), 7, 30 and 90 days, ending today (UTC). Past days are read from the daily summaries, today from the raw page views.
- **Today:** page views and unique visitors.
- **Longer periods:** a daily chart of page views and unique visitors as grouped bars, each bar's date and value on hover; day labels every day up to 7 days, every 3rd up to 30, every 7th beyond; a note that visitors are counted per day.
- **Top pages** (20): path, views, unique visitors.
- **Top referrers:** site and views, 15 a page (`referrer_page`).
- **Devices and browsers:** name, count and share (percent, one decimal).
- Each section says so when it has nothing for the period.

## Findings

- The period was a button event, not in the URL: a reload or a shared link always showed today.
- Only a single day showed totals; longer periods had none.
- The chart was the site's only d3 use (four packages and the `DailyChart` hook), colored with hex values, with a tooltip styled inline.

## Approved changes

- **On the design system** (Jeff approved the mockup, 2026-11-05).
  - The period is `?range=` (`chip_nav` "Period"); an unknown value is today.
  - Totals for every period: today, page views and unique visitors; longer periods, page views, visitors a day on average, and views on the busiest day (with its date).
  - The chart is `bar_chart` (server SVG; the browser's tooltip shows each bar's date and value, after its usual delay; the "Date" and "Count" axis titles are dropped for the legend). d3 and `DailyChart` are removed.
  - Top pages and referrers are `data_table`s (numbers right-aligned; each page path links to the page; paths stay paths, no name lookup, per Jeff). Devices and browsers are `share_list`s.
