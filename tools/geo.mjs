/** Haversine distance in km between two { latitude, longitude } points. */
export function km(a, b) {
  const R = 6371, toR = (x) => (x * Math.PI) / 180;
  const dLa = toR(b.latitude - a.latitude), dLo = toR(b.longitude - a.longitude);
  const h = Math.sin(dLa / 2) ** 2 +
    Math.cos(toR(a.latitude)) * Math.cos(toR(b.latitude)) * Math.sin(dLo / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
