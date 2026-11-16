import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "GreenGuard AI",
  description: "Smart Farming Platform for Lettuce Disease Detection & Marketplace",
  icons: {
    icon: "/green.png",           // Latest logo as favicon
    apple: "/green.png",
    shortcut: "/green.png",
  },
};


export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
  lang="en"
  suppressHydrationWarning
  className="h-full antialiased"
>
  <body suppressHydrationWarning className="min-h-full flex flex-col">
    {children}
  </body>
</html>
  );
}
