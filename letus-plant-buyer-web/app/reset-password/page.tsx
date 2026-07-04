"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";
import Link from "next/link";

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [isSuccess, setIsSuccess] = useState(false);

  // Force sign out on page load to prevent admin redirect
  useEffect(() => {
    supabase.auth.signOut();
  }, []);

  const isLengthValid = password.length >= 6;
  const doPasswordsMatch = password.length > 0 && password === confirmPassword;
  const isFormValid = isLengthValid && doPasswordsMatch;

  async function handlePasswordReset(e: React.FormEvent) {
    e.preventDefault();

    if (!isFormValid) {
      setMessage("Please complete all password requirements.");
      return;
    }

    setLoading(true);
    setMessage("");

    const { error } = await supabase.auth.updateUser({
      password: password.trim(),
    });

    if (error) {
      setMessage(error.message);
      setIsSuccess(false);
    } else {
      setIsSuccess(true);
      setMessage("Password updated successfully! Redirecting to login...");

      await supabase.auth.signOut(); // Extra safety

      setTimeout(() => {
        window.location.href = "/";
      }, 2000);
    }

    setLoading(false);
  }

  return (
    <main className="min-h-screen bg-[#F8FAF7] flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-10">
          <div className="mx-auto mb-6 h-24 w-24 rounded-3xl bg-white p-4 shadow-xl">
            <img src="/green.png" alt="GreenGuard AI" className="h-full w-full object-contain" />
          </div>
          <h1 className="text-4xl font-black text-[#1E2A1F]">Reset Password</h1>
          <p className="mt-2 text-[#5C6B5D]">Create a new secure password</p>
        </div>

        <div className="bg-white rounded-3xl shadow-xl p-8 border border-gray-100">
          {message && (
            <div className={`mb-6 p-4 rounded-2xl text-sm font-medium ${isSuccess ? "bg-green-50 text-green-700" : "bg-red-50 text-red-700"}`}>
              {isSuccess ? "✅" : "⚠️"} {message}
            </div>
          )}

          <form onSubmit={handlePasswordReset} className="space-y-6">
            <div>
              <label className="block text-xs font-bold uppercase tracking-widest text-gray-500 mb-2">New Password</label>
              <div className="relative">
                <input
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  disabled={loading || isSuccess}
                  className="w-full rounded-2xl border border-gray-200 bg-white px-5 py-4 focus:border-[#2F6B3B] outline-none"
                />
                <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-4 top-4 text-gray-400">
                  {showPassword ? "Hide" : "Show"}
                </button>
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold uppercase tracking-widest text-gray-500 mb-2">Confirm New Password</label>
              <input
                type={showPassword ? "text" : "password"}
                placeholder="••••••••"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                disabled={loading || isSuccess}
                className="w-full rounded-2xl border border-gray-200 bg-white px-5 py-4 focus:border-[#2F6B3B] outline-none"
              />
            </div>

            <button
              type="submit"
              disabled={!isFormValid || loading || isSuccess}
              className="w-full py-4 rounded-2xl bg-[#2F6B3B] text-white font-bold text-base disabled:opacity-50 transition hover:bg-[#1E2A1F]"
            >
              {loading ? "Updating Password..." : isSuccess ? "Password Updated ✓" : "Update Password"}
            </button>
          </form>

          <div className="text-center mt-6">
            <Link href="/" className="text-sm text-gray-500 hover:text-[#2F6B3B]">← Back to Store</Link>
          </div>
        </div>
      </div>
    </main>
  );
}