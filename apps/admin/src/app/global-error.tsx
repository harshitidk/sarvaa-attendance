"use client";

export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", padding: 24 }}>
        <h1 style={{ fontSize: 20, fontWeight: 600 }}>Application error</h1>
        <p style={{ color: "#64748b", marginTop: 8 }}>{error.message || "An unexpected error occurred."}</p>
        <button
          onClick={reset}
          style={{
            marginTop: 16,
            padding: "8px 16px",
            borderRadius: 8,
            border: "none",
            background: "#2563eb",
            color: "white",
            cursor: "pointer",
          }}
        >
          Reload
        </button>
      </body>
    </html>
  );
}
