# NWS Weather App — Support Guide

Everything you need to get the most out of the app.

## Contents

- [Getting Started](#getting-started)
- [Home Screen](#home-screen)
- [Locations](#locations)
- [Radar](#radar)
- [Weather AI](#weather-ai)
- [NWS Resources](#nws-resources)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Data Sources](#data-sources)

## Getting Started

On first launch, the app asks for permission to use your location. Allow it so the app can show the official National Weather Service forecast for where you are. You can also skip device location entirely and add cities manually (see [Locations](#locations)).

> **Coverage note:** Forecasts, alerts, and radar come from the U.S. National Weather Service, so the app works for locations in the United States and its territories. Locations outside NWS coverage won't load a forecast.

## Home Screen

The home screen is a single scrolling view. From top to bottom you'll see:

| Card | What it shows |
|---|---|
| Current conditions | Temperature, conditions, and high/low for the active location. |
| Alert banners | Any active NWS alerts for your location. Tap a banner for full details. |
| AI Summary | A plain-language briefing generated on your device. Tap it to open Weather AI chat. |
| Hourly forecast | Hour-by-hour temperatures and conditions. |
| Daily forecast | The multi-day NWS outlook. |
| Condition tiles | Feels-like, humidity, wind, dew point, visibility, pressure, and more from the nearest observation station. |
| Forecast details | The full written NWS forecast discussion for the current period. |
| UV & Sun | UV index, sunrise/sunset arc, daylight stats, and a burn-time estimate. |
| Air quality | Current air quality index for your area. |
| Allergens | Pollen levels (estimated in most U.S. locations — see FAQ). |

**Refresh:** pull down anywhere on the home screen, or use Refresh in the bottom-bar menu.

**Bottom bar:** the map icon opens Radar, the center capsule (showing your location name) opens Locations, and the ⋯ menu holds Ask Weather AI, Refresh, Use Current Location, and NWS Resources.

## Locations

**Add a city** — Open Locations from the bottom bar, type a city name in the search field, then tap a suggestion to add it. The app switches to it immediately.

**Switch locations** — Tap any saved place in the list, or tap **My Location** to return to device GPS.

**Remove a location** — Swipe left on a saved place and tap delete.

Saved places are stored only on your device.

## Radar

Tap the map icon in the bottom bar to open the full-screen radar. All imagery comes directly from NOAA.

### Products

| Product | Use it for |
|---|---|
| Composite | Broad storm view — the best default for "is it raining near me?" |
| Base Refl | Low-level returns from official NOAA regional mosaics. |
| Echo Tops | Storm height and intensity — taller tops mean stronger storms. |
| National Rain | Country-wide precipitation at a glance. |
| Velocity | Inbound/outbound winds from the nearest radar site — useful for rotation. |

### Scope, layers & filters

**Local / National** switches between single-site radar near you and the zoomed-out national view. In Local scope you can tap a radar site on the map to switch to its feed.

**Overlay toggles:** Lightning (GOES satellite strike density), Alerts (active warning polygons), and Tracks (storm direction markers). Your choices are remembered.

**Noise filter** (Local reflectivity only): Off, Light (hides returns below 10 dBZ), or Strong (below 20 dBZ) to clean up clutter near the radar.

### Timeline & inspector

Use the timeline to play or scrub a loop of the past 30 or 50 minutes in 5-minute steps. Tap anywhere on the radar map to inspect what's at that point.

## Weather AI

*On-device.* Weather AI is a chat assistant grounded in the latest NWS forecast, observations, and alerts for your active location. It runs entirely on your device using Apple Intelligence — your questions and weather data never leave your phone.

Open it by tapping the AI summary card or choosing **Ask Weather AI** from the bottom-bar menu. Ask things like "Will it rain during my commute?" or "Should I water the lawn today?"

**Requirements:** Weather AI requires an Apple Intelligence–capable device with Apple Intelligence turned on in Settings. If it's off or unsupported, the app tells you directly in the summary card; everything else in the app works normally without it.

## NWS Resources

Choose **NWS Resources** from the ⋯ menu to browse official NOAA forecast-center products, rendered right in the app:

| Product | Description | Source |
|---|---|---|
| Surface Analysis | Current fronts, highs, and lows. | NOAA WPC |
| Forecast Chart | National synoptic forecast, days 1–3. | NOAA WPC |
| Rainfall Forecast | Official rainfall totals through 5 days. | NOAA WPC |
| Flash Flood Risk | Excessive rainfall outlooks, days 1–3. | NOAA WPC |
| Severe Outlook | Severe thunderstorm outlooks, days 1–3. | NOAA SPC |
| GOES Satellite | Live GeoColor imagery, East & West. | NOAA NESDIS |

The Status section at the bottom shows the app's current weather-data status, active location, and saved-place count — useful when troubleshooting.

## Troubleshooting

**No forecast is loading** — Check that the location is inside the United States — the NWS only covers U.S. locations. Then pull down to refresh, and verify your internet connection. The Status section in NWS Resources shows the exact weather-service status message.

**"My Location" isn't working** — Open iOS Settings → Privacy & Security → Location Services and make sure the app has location access. Alternatively, add your city manually in Locations — device location is never required.

**The AI summary or chat says it's unavailable** — Weather AI needs Apple Intelligence. Turn it on in iOS Settings → Apple Intelligence & Siri. On unsupported devices the feature stays off, but all forecasts, radar, and alerts work normally. If you see "the model is still getting ready," the on-device model is downloading — check back shortly.

**Radar shows no imagery** — Try switching products (Composite is most reliable), or switch the scope between Local and National. Velocity requires a nearby radar site — if none is in range, pick a site manually in Local scope. NOAA radar servers occasionally lag; wait a minute and refresh.

**The radar looks speckled or noisy** — That's ground clutter in the raw single-site feed. Set the Noise filter to Light or Strong while in Local scope.

**Alerts aren't appearing** — Alert banners only appear when the NWS has issued an active alert for your exact location. On the radar, make sure the Alerts overlay toggle is on to see warning polygons.

**Pollen data says "estimated"** — Measured pollen data isn't available for most of the U.S., so the app shows an estimate. This is expected behavior, not an error.

## FAQ

**Where does the weather data come from?**
Forecasts, alerts, and observations come from the National Weather Service (api.weather.gov). Radar imagery comes from NOAA radar servers. UV, sun, and air-quality data come from Open-Meteo. See [Data Sources](#data-sources).

**Is my data private?**
Yes. Saved locations are stored only on your device, and Weather AI runs entirely on-device — chat conversations are never sent to a server.

**Does the app work outside the U.S.?**
No — the National Weather Service covers the U.S. and its territories (including Alaska, Hawaii, the Caribbean, and Guam). Forecasts won't load for international locations.

**How current is the radar?**
Radar tiles update every few minutes as NOAA publishes them. The timeline lets you loop the last 30 or 50 minutes. Satellite imagery in NWS Resources refreshes roughly every 5 minutes.

**What do dBZ values mean on the radar?**
dBZ measures reflectivity — how much precipitation the radar sees. Roughly: under 20 is very light or clutter, 20–40 is light-to-moderate rain, 40–55 is heavy rain, and 55+ can indicate hail.

## Data Sources

| Data | Source |
|---|---|
| Forecasts, observations, alerts | National Weather Service (api.weather.gov) |
| Radar imagery | NOAA NEXRAD / MRMS mosaics (opengeo.ncep.noaa.gov, Iowa Environmental Mesonet cache) |
| Lightning | NOAA nowCOAST — GOES GLM strike density |
| Forecast-center charts | NOAA WPC, SPC, and NESDIS |
| UV index & sun data | Open-Meteo forecast API |
| Air quality & pollen | Open-Meteo air quality API (CAMS model) |
| AI summaries & chat | Apple Intelligence on-device model (no server) |

---

*NWS Weather App Support Guide · All weather data courtesy of NOAA / National Weather Service and Open-Meteo*
