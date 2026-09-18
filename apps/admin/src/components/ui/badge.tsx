import * as React from "react";
import { cn } from "@/lib/utils";

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  tone?: "positive" | "neutral" | "info" | "warning" | "danger";
}

const tones: Record<NonNullable<BadgeProps["tone"]>, string> = {
  positive: "bg-emerald-100 text-emerald-800",
  neutral: "bg-slate-100 text-slate-700",
  info: "bg-blue-100 text-blue-800",
  warning: "bg-amber-100 text-amber-800",
  danger: "bg-red-100 text-red-800",
};

export function Badge({ className, tone = "neutral", ...props }: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
        tones[tone],
        className,
      )}
      {...props}
    />
  );
}
