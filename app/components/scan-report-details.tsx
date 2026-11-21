import { reportGuidance, scanConfidencePercent, type ScanRecord } from "@/lib/scan-guidance";

export function ScanReportDetails({
  log,
  light = false,
  showPhoto = true,
}: {
  log: ScanRecord;
  light?: boolean;
  showPhoto?: boolean;
}) {
  const report = reportGuidance(log);
  const disease = (log.disease_name || log.result || "Unknown result").replaceAll("_", " ");
  const confidence = scanConfidencePercent(log.confidence_score ?? log.confidence);
  const date = log.captured_at || log.created_at;
  const temperature = log.temperature ?? log.temp;
  const weather = log.weather_condition || log.weather;
  const location = log.location?.trim();
  const heading = light ? "text-[#1E2A1F]" : "text-white";
  const content = light ? "border-green-100 text-[#354A38]" : "border-white/15 text-white/85";
  const showLocation = location && !["n/a", "unknown", "no location"].includes(location.toLowerCase());

  return (
    <details className={`group mt-4 rounded-2xl border ${light ? "border-green-200 bg-white" : "border-[#82CF86]/35 bg-[#0A140E]"}`}>
      <summary className={`flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 rounded-2xl px-4 py-3 text-base font-bold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#65B973] ${light ? "text-[#2F6B3B]" : "text-[#A6E59D]"}`}>
        <span className="group-open:hidden">View scan report</span>
        <span className="hidden group-open:inline">Hide scan report</span>
        <span aria-hidden="true" className="text-xl transition-transform group-open:rotate-180">⌄</span>
      </summary>
      <div className={`grid gap-5 border-t p-4 text-base leading-relaxed ${content}`}>
        {report.usesReference && (
          <p className="text-sm">Some guidance comes from the recorded diagnosis. The original scan is unchanged.</p>
        )}
        <div>
          <p className={`font-bold ${heading}`}>{disease}</p>
          <p>AI confidence: {confidence === null ? "Not recorded" : `${confidence.toFixed(1)}%`}</p>
        </div>
        <div>
          <p className={`font-bold ${heading}`}>What is this result?</p>
          <p>{report.diseaseDescription || "No disease explanation was saved."}</p>
          <p className={`mt-3 font-bold ${heading}`}>Associated pathogen</p>
          <p className="italic">{report.pathogen}</p>
          {report.pathogenDescription && <p>{report.pathogenDescription}</p>}
        </div>
        <div>
          <p className={`font-bold ${heading}`}>How to manage it</p>
          {report.treatments.length ? (
            <ul className="mt-1 list-disc space-y-1 pl-6">
              {report.treatments.map((step, index) => <li key={index}>{step}</li>)}
            </ul>
          ) : <p>No management guidance was saved.</p>}
        </div>
        <div className={`rounded-xl border p-3 ${light ? "border-green-100 bg-[#F7FBF6]" : "border-white/10 bg-white/[0.05]"}`}>
          <p className={`font-bold ${heading}`}>Can I sell this lettuce?</p>
          <p className="font-semibold">{report.selling || "Inspect before selling"}</p>
          {report.sellingExplanation && <p>{report.sellingExplanation}</p>}
          <p className="mt-2 text-sm">A photo cannot confirm food safety. Inspect the produce and follow normal food handling requirements.</p>
        </div>
        <div className="text-sm">
          <p className={`text-base font-bold ${heading}`}>Scan information</p>
          <p>Date: {date ? new Date(date).toLocaleString() : "Not recorded"}</p>
          {showLocation && <p>Location: {location}</p>}
          {weather && weather.trim().toLowerCase() !== "n/a" && <p>Weather: {weather}</p>}
          {temperature != null && String(temperature).trim() && Number.isFinite(Number(temperature)) && (
            <p>Temperature: {Number(temperature).toFixed(1)}°C</p>
          )}
          {!log.image_url && <p>Photo not saved</p>}
        </div>
        {showPhoto && log.image_url && (
          // Supabase storage URLs can vary by project.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={log.image_url} alt={`Lettuce photo for ${disease}`} loading="lazy" className="max-h-72 w-full rounded-xl object-contain" />
        )}
      </div>
    </details>
  );
}
