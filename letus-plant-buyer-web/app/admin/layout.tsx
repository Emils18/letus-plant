export default function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen w-full overflow-x-hidden bg-[#07100B] font-sans text-white selection:bg-[#5DBB63] selection:text-[#07100B]">
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -left-[18%] top-[-18%] h-[720px] w-[720px] rounded-full bg-[#5DBB63]/15 blur-[140px]" />
        <div className="absolute -right-[18%] bottom-[-22%] h-[820px] w-[820px] rounded-full bg-[#2F6B3B]/20 blur-[170px]" />
        <div className="absolute left-[35%] top-[20%] h-[420px] w-[420px] rounded-full bg-emerald-400/5 blur-[120px]" />

        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.025)_1px,transparent_1px)] bg-[size:54px_54px]" />
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#07100B]/30 to-[#07100B]" />
      </div>

      <div className="relative z-10 min-h-screen">{children}</div>
    </div>
  );
}