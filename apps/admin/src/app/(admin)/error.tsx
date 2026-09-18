"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function AdminError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[admin error]", error);
  }, [error]);

  return (
    <div className="mx-auto max-w-7xl p-6 text-center lg:p-8">
      <h1 className="text-lg font-semibold">Could not load this page</h1>
      <p className="mt-2 text-sm text-muted-foreground">{error.message}</p>
      <div className="mt-5 flex justify-center gap-2">
        <Button onClick={reset}>Retry</Button>
        <Button variant="outline" onClick={() => (window.location.href = "/dashboard")}>
          Back to dashboard
        </Button>
      </div>
    </div>
  );
}
