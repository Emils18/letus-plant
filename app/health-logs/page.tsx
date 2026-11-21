"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

import { supabase } from "@/lib/supabase";

import { scanClass, scanConfidencePercent, scanPathogen, type ScanRecord } from "@/lib/scan-guidance";

import { ScanReportDetails } from "@/app/components/scan-report-details";

type HealthLog = ScanRecord & {
  id: string;

  user_id?: string | null;

  scan_session_id?: string | null;

  captured_at?: string | null;

  created_at?: string | null;

};

type ScanSession = {
  id: string;

  started_at?: string | null;

  completed_at?: string | null;

  status?: string | null
};

type View = "home" | "overall" | "sessions";

const diseaseNames = ["Downy Mildew", "Powdery Mildew", "Septoria Blight"] as const;

const card = "rounded-3xl border border-emerald-900/10 bg-white p-5 shadow-sm sm:p-7";

const textDate = (value?: string | null) => value && !Number.isNaN(Date.parse(value)) ? new Date(value).toLocaleString() : "Date not recorded";

const disease = (log: HealthLog) => (log.disease_name || log.result || "Unknown result").replaceAll("_", " ").trim();

const isHealthy = (log: HealthLog) => scanClass(disease(log)) === "healthy";

const confidenceValues = (records: HealthLog[]) => records.map((log) => scanConfidencePercent(log.confidence_score ?? log.confidence)).filter((value): value is number => value !== null);

const averageConfidence = (records: HealthLog[]) => {
  const values = confidenceValues(records);

  return values.length ? `${(values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(1)}%` : "Not available";

};

function ScanCard({ log, index }: {
  log: HealthLog;

  index: number
}) {
  const healthy = isHealthy(log);

  const resultClass = scanClass(disease(log));

  const known = ["healthy", "downy mildew", "powdery mildew", "septoria blight"].includes(resultClass);

  return <article className="overflow-hidden rounded-2xl border border-emerald-900/10 bg-white">    {log.image_url ? <img src={log.image_url} alt={`Saved lettuce scan ${index + 1}`} loading="lazy" className="h-52 w-full bg-emerald-50 object-cover sm:h-64" /> : <div className="flex h-40 items-center justify-center bg-emerald-50 text-base font-semibold text-emerald-900/60">Scan image not available</div>}    <div className="p-4 sm:p-5">      <div className="flex flex-wrap items-start justify-between gap-3">
    <div>
      <p className="text-xs font-bold uppercase tracking-wide text-emerald-800/60">Lettuce {index + 1}</p>
      <h4 className="mt-1 text-xl font-extrabold text-slate-900">{disease(log)}</h4>
      <p className="mt-1 text-sm text-slate-600">{textDate(log.captured_at || log.created_at)}</p>
    </div>
    <span className={`rounded-full px-3 py-1.5 text-sm font-bold ${healthy ? "bg-emerald-100 text-emerald-900" : "bg-amber-100 text-amber-900"}`}>{healthy ? "Healthy result" : known ? "Disease detected" : "Uncertain result"}</span>
  </div>      <p className="mt-3 text-sm font-semibold text-slate-700">AI confidence: {scanConfidencePercent(log.confidence_score ?? log.confidence) === null ? "Not available" : `${scanConfidencePercent(log.confidence_score ?? log.confidence)!.toFixed(1)}%`}</p>      <p className="mt-1 text-sm text-slate-600">Pathogen: {scanPathogen(log)}</p>      <ScanReportDetails log={log} light showPhoto={false} />    </div>  </article>;

}
export default function HealthLogsPage() {
  const [logs, setLogs] = useState<HealthLog[]>([]);

  const [sessions, setSessions] = useState<ScanSession[]>([]);

  const [loading, setLoading] = useState(true);

  const [error, setError] = useState("");

  const [view, setView] = useState<View>("home");

  const [showAll, setShowAll] = useState(false);

  const [openSession, setOpenSession] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);

    setError("");

    try {
      const { data: { user } } = await supabase.auth.getUser();

      if(!user) throw new Error("Please log in to view your saved health reports.");

      const [logsResult, sessionsResult] = await Promise.all([supabase.from("diagnostic_logs").select("*").eq("user_id", user.id).order("created_at", { ascending: false }), supabase.from("scan_sessions").select("id, started_at, completed_at, status").eq("user_id", user.id).order("started_at", { ascending: false }),]);

      if(logsResult.error) throw new Error(logsResult.error.message);

      if(sessionsResult.error) throw new Error(sessionsResult.error.message);

      const unique = new Map<string, HealthLog>();

      for(const item of(logsResult.data || []) as HealthLog[]) unique.set(String(item.id), item);

      setLogs([...unique.values()].sort((a, b) => Date.parse(b.captured_at || b.created_at || "") - Date.parse(a.captured_at || a.created_at || "")));

      setSessions((sessionsResult.data || []) as ScanSession[]);

    } catch(err) {
      setError(err instanceof Error ? err.message : "Could not load saved reports.");

    } finally {
      setLoading(false);

    }
  }, []);

  useEffect(() => {
    void load();

  }, [load]);

  const healthyCount = useMemo(() => logs.filter(isHealthy).length, [logs]);

  const atRiskCount = logs.length - healthyCount;

  const standalone = useMemo(() => logs.filter((log) => !log.scan_session_id), [logs]);

  const diseaseCount = (name: string, list = logs) => list.filter((log) => scanClass(disease(log)) === scanClass(name)).length;

  const sessionsWithScans = sessions.map((session) => ({ session, scans: logs.filter((log) => String(log.scan_session_id || "") === session.id).sort((a, b) => Date.parse(a.captured_at || a.created_at || "") - Date.parse(b.captured_at || b.created_at || "")) })).filter((item) => item.scans.length > 0);

  const knownSessionIds = new Set(sessions.map((session) => session.id));

  const orphanSessionReports = [...new Set(logs.map((log) => log.scan_session_id).filter((id): id is string => Boolean(id) && !knownSessionIds.has(id!)))].map((id) => ({ session: { id, started_at: null }, scans: logs.filter((log) => log.scan_session_id === id).sort((a, b) => Date.parse(a.captured_at || a.created_at || "") - Date.parse(b.captured_at || b.created_at || "")) }));

  const allSessionReports = [...sessionsWithScans, ...orphanSessionReports];

  const progress = (value: number) => logs.length ? value / logs.length * 100 : 0;

  const overallSummary = logs.length === 0 ? "No saved lettuce scans yet." : atRiskCount === 0 ? "All saved scans were classified as healthy. Inspect every lettuce before selling." : `${atRiskCount} of ${logs.length} saved scans need closer inspection. Separate affected produce and review its individual report.`;

  const recommendation = atRiskCount ? "Set aside lettuce with disease or uncertain results, inspect nearby plants, and follow the care steps in each report." : "Continue routine crop checks and inspect produce before harvest and sale.";

  return <main className="min-h-screen bg-[#F4F8F3] text-slate-900">    <header className="border-b border-emerald-950/10 bg-white">
    <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-5 sm:px-7">
      <div>
        <p className="text-sm font-extrabold uppercase tracking-widest text-emerald-800">GreenGuard AI</p>
        <h1 className="mt-1 text-2xl font-black sm:text-3xl">Health Logs</h1>
      </div>
      <div className="flex gap-2">
        <button onClick={() => setView("home")} className="min-h-11 rounded-xl border px-4 font-bold">Reports</button>
        <button onClick={() => void load()} disabled={loading} className="min-h-11 rounded-xl bg-emerald-800 px-4 font-bold text-white disabled:opacity-60">{loading ? "Loading…" : "Refresh"}</button>
      </div>
    </div>
  </header>    <div className="mx-auto max-w-6xl px-4 py-7 sm:px-7 sm:py-10">      {error && <div role="alert" className="mb-5 rounded-2xl border border-red-200 bg-red-50 p-4 font-semibold text-red-900">{error} <button className="ml-2 underline" onClick={() => void load()}>Try again</button>
  </div>}      {loading ? <div className="py-20 text-center text-lg font-bold text-emerald-900">Loading saved scan reports…</div> : <>        {view === "home" && <>
    <div className="mb-7">
      <h2 className="text-2xl font-black sm:text-3xl">Your lettuce health reports</h2>
      <p className="mt-2 max-w-2xl text-base text-slate-600">Choose an overview of all saved scans or open one specific scanning session.</p>
    </div>
    <div className="grid gap-5 md:grid-cols-2">          <button onClick={() => {
      setView("overall");

      setShowAll(false);

    }} className="group rounded-3xl border border-emerald-800/20 bg-gradient-to-br from-emerald-900 to-emerald-700 p-7 text-left text-white shadow-lg transition hover:-translate-y-0.5 focus-visible:outline-4 focus-visible:outline-emerald-400">
      <span className="text-sm font-bold uppercase tracking-widest text-emerald-100">All saved scans</span>
      <h3 className="mt-3 text-2xl font-black">Overall Health Report</h3>
      <p className="mt-2 text-emerald-50">Crop summary, percentages, disease breakdown, and average AI confidence.</p>
      <div className="mt-6 flex items-end justify-between">
        <b className="text-4xl">{logs.length}</b>
        <span className="font-bold">lettuce scanned →</span>
      </div>
    </button>          <button onClick={() => setView("sessions")} className="group rounded-3xl border border-emerald-800/15 bg-white p-7 text-left shadow-sm transition hover:-translate-y-0.5 focus-visible:outline-4 focus-visible:outline-emerald-400">
        <span className="text-sm font-bold uppercase tracking-widest text-emerald-800">Independent reports</span>
        <h3 className="mt-3 text-2xl font-black">Session Reports</h3>
        <p className="mt-2 text-slate-600">Open a session to see only the lettuces saved in that scan.</p>
        <div className="mt-6 flex items-end justify-between">
          <b className="text-4xl text-emerald-800">{allSessionReports.length + standalone.length}</b>
          <span className="font-bold text-emerald-900">sessions and individual scans →</span>
        </div>
      </button>        </div>
    <p className="mt-6 text-sm text-slate-500">Reports use saved scan results. AI image classification is not a food-safety guarantee.</p>
  </>}        {view === "overall" && <>
    <button onClick={() => setView("home")} className="mb-5 min-h-11 rounded-xl border border-emerald-900/15 bg-white px-4 font-bold text-emerald-900">← All reports</button>
    <section className={card}>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-sm font-bold uppercase tracking-widest text-emerald-800">All saved scan records</p>
          <h2 className="mt-1 text-3xl font-black">Overall Health Report</h2>
        </div>
        <span className="rounded-full bg-emerald-100 px-4 py-2 font-extrabold text-emerald-900">{logs.length} scanned</span>
      </div>          <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Healthy lettuce" value={`${healthyCount}`} note={`${progress(healthyCount).toFixed(1)}% of scans`} />
        <Metric label="Unhealthy / at risk" value={`${atRiskCount}`} note={`${progress(atRiskCount).toFixed(1)}% of scans`} tone="amber" />
        <Metric label="Average AI confidence" value={averageConfidence(logs)} note="Valid saved confidence values" />
        <Metric label="Total scanned" value={`${logs.length}`} note="Unique saved scan records" />
      </div>          <div className="mt-6 grid gap-6 lg:grid-cols-2">
        <div className="rounded-2xl bg-emerald-50 p-5">
          <h3 className="text-lg font-extrabold">Crop health summary</h3>
          <p className="mt-2 leading-7 text-slate-700">{overallSummary}</p>
          <h4 className="mt-5 font-extrabold">Practical next steps</h4>
          <p className="mt-2 leading-7 text-slate-700">{recommendation}</p>
        </div>
        <div className="rounded-2xl border border-slate-200 p-5">
          <h3 className="text-lg font-extrabold">Detected disease breakdown</h3>{diseaseNames.map((name) => {
            const count = diseaseCount(name);

            return <div key={name} className="mt-4">
              <div className="flex justify-between gap-3 text-sm font-bold">
                <span>{name}</span>
                <span>{count}</span>
              </div>
              <div className="mt-2 h-3 overflow-hidden rounded-full bg-slate-100">
                <div className="h-full rounded-full bg-amber-500" style={{ width: `${logs.length ? count / logs.length * 100 : 0}%` }} />
              </div>
            </div>
          })}<div className="mt-5 flex justify-between text-sm font-bold">
            <span>Healthy</span>
            <span>{healthyCount}</span>
          </div>
          <div className="mt-2 h-3 overflow-hidden rounded-full bg-slate-100">
            <div className="h-full rounded-full bg-emerald-600" style={{ width: `${progress(healthyCount)}%` }} />
          </div>
        </div>
      </div>          <button onClick={() => setShowAll((value) => !value)} className="mt-6 min-h-12 w-full rounded-xl bg-emerald-800 px-5 font-extrabold text-white">{showAll ? "Hide scanned lettuces" : "View All Scanned Lettuces"}</button>          {showAll && <div className="mt-5 grid gap-4 md:grid-cols-2">{logs.map((log, index) => <ScanCard key={log.id} log={log} index={index} />)}{logs.length === 0 && <Empty text="No saved lettuce scans yet." />}</div>}        </section>
  </>}        {view === "sessions" && <>
    <button onClick={() => setView("home")} className="mb-5 min-h-11 rounded-xl border border-emerald-900/15 bg-white px-4 font-bold text-emerald-900">← All reports</button>
    <div className="mb-5">
      <h2 className="text-3xl font-black">Session Reports</h2>
      <p className="mt-2 text-slate-600">Every report stays with its saved session ID. Individual scans without a session appear on their own.</p>
    </div>          {allSessionReports.map(({ session, scans }) => {
      const healthy = scans.filter(isHealthy).length;

      const risk = scans.length - healthy;

      const opened = openSession === session.id;

      return <section key={session.id} className={`${card} mb-4`}>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="text-xl font-extrabold">Scan session</h3>
            <p className="mt-1 text-sm text-slate-600">{session.started_at ? `Started ${textDate(session.started_at)}` : "Session date not recorded"}</p>
          </div>
          <span className="rounded-full bg-emerald-100 px-3 py-2 font-bold text-emerald-900">{scans.length} lettuce scanned</span>
        </div>
        <div className="mt-4 grid grid-cols-2 gap-2 text-sm sm:grid-cols-5">
          <SmallMetric label="Healthy" value={healthy} />
          <SmallMetric label="At risk" value={risk} />
          <SmallMetric label="Downy" value={diseaseCount("Downy Mildew", scans)} />
          <SmallMetric label="Powdery" value={diseaseCount("Powdery Mildew", scans)} />
          <SmallMetric label="Septoria" value={diseaseCount("Septoria Blight", scans)} />
        </div>
        <p className="mt-3 text-sm font-bold text-slate-700">Average confidence: {averageConfidence(scans)}</p>
        <p className="mt-2 text-sm leading-6 text-slate-600">{risk ? `${risk} lettuce need closer inspection. Check each scan report for disease-specific care.` : "Every scan in this session was classified as healthy. Inspect before selling."}</p>
        <button onClick={() => setOpenSession(opened ? null : session.id)} className="mt-4 min-h-12 w-full rounded-xl bg-emerald-800 px-5 font-extrabold text-white">{opened ? "Hide scanned lettuces" : "View Scanned Lettuces"}</button>{opened && <div className="mt-4 grid gap-4 md:grid-cols-2">{scans.map((log, index) => <ScanCard key={log.id} log={log} index={index} />)}</div>}</section>
    })}          {standalone.length > 0 && <section className={`${card} mt-7`}>
      <h3 className="text-2xl font-black">Individual Scan Reports</h3>
      <p className="mt-1 text-slate-600">These saved scans do not have a session ID, so each is shown independently.</p>
      <div className="mt-4 grid gap-4 md:grid-cols-2">{standalone.map((log, index) => <ScanCard key={log.id} log={log} index={index} />)}</div>
    </section>}          {!allSessionReports.length && !standalone.length && <Empty text="No saved session or individual scan reports yet." />}        </>}      </>}    </div>  </main>;

}
function Metric({ label, value, note, tone }: {
  label: string;

  value: string;

  note: string;

  tone?: "amber"
}) {
  return <div className={`rounded-2xl p-4 ${tone === "amber" ? "bg-amber-50" : "bg-emerald-50"}`}>
    <p className="text-sm font-bold text-slate-600">{label}</p>
    <p className={`mt-2 text-3xl font-black ${tone === "amber" ? "text-amber-800" : "text-emerald-900"}`}>{value}</p>
    <p className="mt-1 text-xs text-slate-500">{note}</p>
  </div>;

}
function SmallMetric({ label, value }: {
  label: string;

  value: number
}) {
  return <div className="rounded-xl bg-slate-50 p-3">
    <span className="text-slate-600">{label}</span>
    <b className="mt-1 block text-xl">{value}</b>
  </div>;

}
function Empty({ text }: { text: string }) {
  return <div className="rounded-2xl border border-dashed border-emerald-900/20 bg-white p-8 text-center text-slate-600">{text}</div>;

}



