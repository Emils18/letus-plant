export default function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen w-full bg-[#F6FBF6] font-sans text-[#1E2A1F] selection:bg-[#2F6B3B] selection:text-white">
      {/* Subtle Premium Background Glows */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div className="absolute -left-[10%] top-[-5%] h-[600px] w-[600px] animate-pulse rounded-full bg-[#5DBB63]/10 blur-[120px] duration-[7000ms]" />
        <div className="absolute -right-[10%] bottom-[-10%] h-[800px] w-[800px] animate-pulse rounded-full bg-[#2F6B3B]/5 blur-[150px] duration-[10000ms] delay-500" />
      </div>
      
      {/* Page Content Wrapper */}
      <div className="relative z-10 flex min-h-screen w-full flex-col">
        {children}
      </div>
    </div>
  );
}