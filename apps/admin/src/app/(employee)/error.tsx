"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function EmployeeError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error("[employee error]", error);
  }, [error]);

  return (
    <div className="mx-auto max-w-3xl px-4 py-10 text-center">
      <h1 className="text-lg font-semibold">Could not load your attendance</h1>
      <p className="mt-2 text-sm text-muted-foreground">{error.message}</p>
      <div className="mt-5 flex justify-center gap-2">
        <Button onClick={reset}>Retry</Button>
        <Button variant="outline" onClick={() => (window.location.href = "/employee")}>
          Reload
        </Button>
      </div>
    </div>
  );
}
