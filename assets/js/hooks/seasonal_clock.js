// The reference rows come from Phenology.SeasonalClock.reference/0, not a
// separately maintained climate file. Forward/inverse math mirrors that module.
export function createClock(rows) {
  if (!Array.isArray(rows) || rows.length < 2 || rows.some((row, i) =>
    row.length !== 3 || !row.every(Number.isFinite) || row[1] >= row[2] ||
    row[2] >= row[1] + 365 || (i > 0 && row[0] <= rows[i - 1][0]))) {
    throw new Error('Invalid seasonal-landmark reference')
  }
  const latitudes = rows.map(row => row[0])
  const supported = lat => Number.isFinite(lat) && lat >= latitudes[0] && lat <= latitudes.at(-1)
  const anchors = lat => {
    if (!supported(lat)) return null
    const i = rows.findIndex(row => row[0] >= lat)
    const [l1, s1, a1] = rows[i]
    const [l0, s0, a0] = rows[Math.max(0, i - 1)]
    const f = l0 === l1 ? 0 : (lat - l0) / (l1 - l0)
    return [s0 + f * (s1 - s0), a0 + f * (a1 - a0)]
  }
  const coordinate = (day, lat) => {
    const pair = anchors(lat)
    if (!pair || !Number.isFinite(day)) return null
    const [s, a] = pair
    const year = Math.floor((day - s) / 365)
    const d = day - year * 365
    return year * 365 + (d <= a ? (d - s) / (a - s) * 182.5
      : 182.5 + (d - a) / (s + 365 - a) * 182.5)
  }
  const inverse = (phase, lat) => {
    const pair = anchors(lat)
    if (!pair || !Number.isFinite(phase)) return null
    const [s, a] = pair
    const year = Math.floor(phase / 365)
    const p = phase - year * 365
    return year * 365 + (p <= 182.5 ? s + p / 182.5 * (a - s)
      : a + (p - 182.5) / 182.5 * (s + 365 - a))
  }
  const window = (doy, lat, days) => {
    if (!Number.isInteger(doy) || doy < 1 || doy > 366 || !supported(lat) ||
      !Number.isFinite(days) || days < 0 || days > 183) return null
    return {low: coordinate(doy - days, lat), high: coordinate(doy + days, lat)}
  }
  return {latitudes, supported, coordinate, inverse, window}
}

export function inWindow(phase, {low, high}) {
  if (!Number.isFinite(phase)) return false
  const offset = ((phase - low) % 365 + 365) % 365
  return high - low >= 365 || offset <= high - low + 1e-8 || offset >= 365 - 1e-8
}
