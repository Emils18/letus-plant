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
        setCoordinates("");
        setLocationError(error.code === 1
          ? "Location access is off. Allow it in your browser to use local weather."
          : "Could not determine your location. Try again when GPS is available.");
      },
      { enableHighAccuracy: false, timeout: 12000, maximumAge: 60000 },
    );
  }

  useEffect(() => () => {
    if (watch.current !== null) navigator.geolocation.clearWatch(watch.current);
  }, []);

  return { coordinates, locationError, useCurrentLocation };
}
