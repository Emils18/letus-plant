"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import { useRouter } from "next/navigation";
import Link from "next/link";

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [isSuccess, setIsSuccess] = useState(false);
  const [isRecoveryActive, setIsRecoveryActive] = useState(false);

  const router = useRouter();

  // Dynamic Validation Checks
  const isLengthValid = password.length >= 6;
  const doPasswordsMatch = password.length > 0 && password === confirmPassword;
  const isFormValid = isLengthValid && doPasswordsMatch;

  useEffect(() => {
    // Check if we have an active session (Supabase handles the hash automatically on mount)
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) {
        setIsRecoveryActive(true);
      } else {
        // Look at the URL hash for recovery parameters
        if (window.location.hash.includes("access_token")) {
          setIsRecoveryActive(true);
        } else {
          setMessage("Invalid or expired session. Please request a new password reset link from the login page.");
          setIsSuccess(false);
        }
      }
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "PASSWORD_RECOVERY" || session) {
        setIsRecoveryActive(true);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  async function handlePasswordReset(e: React.FormEvent) {
    e.preventDefault();

    if (!isFormValid) {
      setMessage("Please complete all password requirements.");
      setIsSuccess(false);
      return;
    }

    setLoading(true);
    setMessage("");

    const { error } = await supabase.auth.updateUser({
      password,
    });

    if (error) {
      setLoading(false);
      setIsSuccess(false);
      setMessage(error.message);
      return;
    }

    setLoading(false);
    setIsSuccess(true);
    setMessage("Password updated successfully! Redirecting...");

    setTimeout(() => {
      router.push("/");
    }, 2000);
  }

  return (
    <main className="relative flex min-h-screen w-full items-center justify-center overflow-hidden bg-[#F7FBF6] px-4 py-12">
      
      {/* Soft Animated Background Blobs */}
      <div className="absolute left-[-15%] top-[-10%] h-[600px] w-[600px] animate-pulse rounded-full bg-[#5DBB63]/15 blur-[120px]" />
      <div className="absolute bottom-[-15%] right-[-15%] h-[700px] w-[700px] animate-pulse rounded-full bg-[#2F6B3B]/10 blur-[140px]" />

      {/* Premium Card */}
      <div className="relative z-10 w-full max-w-md overflow-hidden rounded-3xl border border-[#E5EDE3] bg-white shadow-2xl shadow-[#5DBB63]/10 backdrop-blur-2xl transition-all duration-500 hover:shadow-[#5DBB63]/20">
        
        {/* Accent Top Bar */}
        <div className="h-2.5 w-full bg-gradient-to-r from-[#2F6B3B] via-[#5DBB63] to-[#2F6B3B]" />

        <div className="px-8 pb-10 pt-9">
          
          {/* Header */}
          <div className="mb-10 flex flex-col items-center text-center">
            <div className="mb-6 flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br from-[#2F6B3B] to-[#5DBB63] text-white shadow-xl shadow-[#5DBB63]/30 transition-transform hover:scale-110">
              <svg className="h-10 w-10" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth="2.25">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M2.458 12C3.732 7.943 7.523 5 12 5 16.477 5 20.268 7.943 21.542 12 20.268 16.057 16.477 19 12 19 7.523 19 3.732 16.057 2.458 12z" />
              </svg>
            </div>
            
            <h1 className="text-3xl font-black tracking-tighter text-[#1E2A1F]">Reset Password</h1>
            <p className="mt-3 text-sm text-[#5C6B5D] max-w-[280px]">
              Create a strong new password for your LetUs Plant account
            </p>
          </div>

          {/* Message Toast */}
          {message && (
            <div className={`mb-6 flex items-center gap-3 rounded-2xl px-5 py-4 text-sm font-medium transition-all duration-300 ${
              isSuccess 
                ? "bg-green-50 border border-green-200 text-green-700" 
                : "bg-red-50 border border-red-200 text-red-700"
            }`}>
              {isSuccess ? "✅" : "⚠️"} {message}
            </div>
          )}

          <form onSubmit={handlePasswordReset} className="space-y-6">
            
            {/* New Password */}
            <div className="space-y-2">
              <label className="block text-xs font-bold uppercase tracking-widest text-[#5C6B5D]">New Password</label>
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={loading || isSuccess || !isRecoveryActive}
                  className="w-full rounded-2xl border border-[#E5EDE3] bg-white px-6 py-4 text-[#1E2A1F] placeholder:text-gray-400 focus:border-[#5DBB63] focus:ring-4 focus:ring-[#5DBB63]/10 transition-all disabled:opacity-60"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-5 top-1/2 -translate-y-1/2 text-sm font-semibold text-[#5C6B5D] hover:text-[#2F6B3B] transition-colors"
                >
                  {showPassword ? "Hide" : "Show"}
                </button>
              </div>
            </div>

            {/* Confirm Password */}
            <div className="space-y-2">
              <label className="block text-xs font-bold uppercase tracking-widest text-[#5C6B5D]">Confirm New Password</label>
              <input
                type={showPassword ? "text" : "password"}
                placeholder="••••••••"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                disabled={loading || isSuccess || !isRecoveryActive}
                className="w-full rounded-2xl border border-[#E5EDE3] bg-white px-6 py-4 text-[#1E2A1F] placeholder:text-gray-400 focus:border-[#5DBB63] focus:ring-4 focus:ring-[#5DBB63]/10 transition-all disabled:opacity-60"
              />
            </div>

            {/* Security Checklist */}
            <div className="rounded-2xl bg-[#F7FBF6] p-6 border border-[#E5EDE3]">
              <p className="mb-4 text-[10px] font-black uppercase tracking-[1px] text-[#5C6B5D]">Password Requirements</p>
              <div className="space-y-3.5">
                <div className={`flex items-center gap-3 text-sm transition-all duration-300 ${isLengthValid ? "text-[#2F6B3B]" : "text-gray-400"}`}>
                  <div className={`h-5 w-5 rounded-full flex items-center justify-center border transition-all ${isLengthValid ? "border-[#2F6B3B] bg-[#2F6B3B]" : "border-gray-300"}`}>
                    {isLengthValid && <span className="text-white text-xs">✓</span>}
                  </div>
                  At least 6 characters long
                </div>

                <div className={`flex items-center gap-3 text-sm transition-all duration-300 ${doPasswordsMatch ? "text-[#2F6B3B]" : "text-gray-400"}`}>
                  <div className={`h-5 w-5 rounded-full flex items-center justify-center border transition-all ${doPasswordsMatch ? "border-[#2F6B3B] bg-[#2F6B3B]" : "border-gray-300"}`}>
                    {doPasswordsMatch && <span className="text-white text-xs">✓</span>}
                  </div>
                  Passwords match
                </div>
              </div>
            </div>

            {/* Submit Button */}
            <button
              type="submit"
              disabled={!isFormValid || loading || isSuccess || !isRecoveryActive}
              className="mt-4 w-full rounded-2xl bg-gradient-to-r from-[#2F6B3B] to-[#5DBB63] py-4 text-base font-bold text-white shadow-lg shadow-[#5DBB63]/30 transition-all hover:-translate-y-0.5 hover:shadow-xl active:scale-[0.985] disabled:cursor-not-allowed disabled:opacity-60"
            >
              {loading ? (
                <span className="flex items-center justify-center gap-3">
                  <svg className="h-5 w-5 animate-spin" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                  </svg>
                  Updating Password...
                </span>
              ) : isSuccess ? (
                "Password Updated ✓"
              ) : (
                "Update Password"
              )}
            </button>
          </form>

          {/* Cancel Link */}
          {!isSuccess && (
            <div className="mt-8 text-center">
              <Link href="/" className="text-sm font-medium text-[#5C6B5D] hover:text-[#2F6B3B] transition-colors">
                ← Back to Store
              </Link>
            </div>
          )}
        </div>
      </div>
    </main>
  );
}