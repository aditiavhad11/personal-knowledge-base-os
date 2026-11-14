import type { Metadata } from "next";
import "@fontsource-variable/inter";
import ErrorBoundary from "@/components/ErrorBoundary";
import NavBar from "@/components/NavBar";
import "./globals.css";

export const metadata: Metadata = {
  title: "Knowledge Base OS",
  description:
    "A local-first personal knowledge base: search, browse, visualize, and chat with your markdown notes.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body
        className="min-h-screen bg-ink-50 text-ink-900 antialiased"
        style={{
          fontFamily: '"Inter Variable", system-ui, sans-serif',
        }}
      >
        <NavBar />
        <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
          <ErrorBoundary>{children}</ErrorBoundary>
        </main>
        <footer className="border-t border-ink-200 bg-white">
          <div className="mx-auto max-w-7xl px-4 py-6 text-center text-xs text-ink-400 sm:px-6">
            Knowledge Base OS — local-first, offline by default. Built with Next.js.
          </div>
        </footer>
      </body>
    </html>
  );
}
