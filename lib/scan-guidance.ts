import catalog from "./scan-guidance.json" with { type: "json" };

export type ScanRecord = {
  disease_name?: string | null;
  result?: string | null;
  confidence_score?: number | string | null;
  confidence?: number | string | null;
  image_url?: string | null;
  captured_at?: string | null;
  created_at?: string | null;
  location?: string | null;
  temperature?: number | string | null;
  temp?: number | string | null;
  weather_condition?: string | null;
  weather?: string | null;
  pathogen_name?: string | null;
  disease_description?: string | null;
  pathogen_description?: string | null;
  treatment_recommendations?: string[] | string | null;
  selling_recommendation?: string | null;
  selling_explanation?: string | null;
};

export function scanClass(value?: string | null): string {
  const name = value?.trim().toLowerCase().replace(/[\s_-]+/g, " ") || "";
  if (name === "septoria leaf spot" || name === "septoria") return "septoria blight";
  if (["no disease", "none", "none detected"].includes(name)) return "healthy";
  return name;
}

export function scanGuidance(value?: string | null) {
  const key = scanClass(value);
  return Object.hasOwn(catalog, key) ? catalog[key as keyof typeof catalog] : null;
}

export function scanConfidencePercent(raw?: string | number | null) {
  if (raw == null) return null;
  const text = String(raw).trim();
  const isPercentage = text.endsWith("%");
  const amount = isPercentage ? text.slice(0, -1).trim() : text;
  if (!amount) return null;
  const value = Number(amount);
  if (!Number.isFinite(value) || value < 0 || value > 100) return null;
  return !isPercentage && value <= 1 ? value * 100 : value;
}

export function scanPathogen(log: ScanRecord) {
  const stored = log.pathogen_name?.trim();
  return stored || scanGuidance(log.disease_name || log.result)?.pathogen_name || "Not recorded";
}

export function reportGuidance(log: ScanRecord) {
  const reference = scanGuidance(log.disease_name || log.result);
  const savedTreatments = Array.isArray(log.treatment_recommendations)
    ? log.treatment_recommendations.filter((item) => typeof item === "string" && item.trim())
    : typeof log.treatment_recommendations === "string" && log.treatment_recommendations.trim()
      ? [log.treatment_recommendations.trim()]
      : [];
  return {
    usesReference: Boolean(reference && (!log.disease_description?.trim() ||
      !log.pathogen_description?.trim() || !log.pathogen_name?.trim() ||
      !savedTreatments.length || !log.selling_recommendation?.trim() ||
      !log.selling_explanation?.trim())),
    pathogen: scanPathogen(log),
    diseaseDescription: log.disease_description?.trim() || reference?.disease_description,
    pathogenDescription: log.pathogen_description?.trim() || reference?.pathogen_description,
    treatments: savedTreatments.length ? savedTreatments : reference?.treatment_recommendations || [],
    selling: log.selling_recommendation?.trim() || reference?.selling_recommendation,
    sellingExplanation: log.selling_explanation?.trim() || reference?.selling_explanation,
  };
}
