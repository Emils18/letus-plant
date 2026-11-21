"use client";

import { useEffect, useRef, useState } from "react";

export function useWeatherLocation() {
  const [coordinates, setCoordinates] = useState("");
  const [locationError, setLocationError] = useState("");
  const watch = useRef<number | null>(null);

  function useCurrentLocation() {
    if (!navigator.geolocation) {
      setLocationError("This browser cannot share your location.");
      return;
    }
    if (watch.current !== null) navigator.geolocation.clearWatch(watch.current);
    setLocationError("");
    watch.current = navigator.geolocation.watchPosition(
      ({ coords }) => {
        setLocationError("");
        setCoordinates(`${coords.latitude.toFixed(2)},${coords.longitude.toFixed(2)}`);
      },
      (error) => {
        // Preserve the last known coordinates when GPS temporarily fails.
        // A warning remains visible so outdated coordinates are not mistaken
        // for a fresh location reading.
        setLocationError(error.code === 1
          ? "Location permission is denied. Previously detected coordinates may be outdated."
          : "Could not refresh GPS. Previously detected coordinates, if available, may be outdated.");
      },
      { enableHighAccuracy: false, timeout: 12000, maximumAge: 60000 },
    );
  }

  useEffect(() => () => {
    if (watch.current !== null) navigator.geolocation.clearWatch(watch.current);
  }, []);

  return { coordinates, locationError, useCurrentLocation };
}
