export const colors = {
  background: "#f8fafc",
  card: "#ffffff",
  foreground: "#0f172a",
  muted: "#64748b",
  border: "#e2e8f0",
  primary: "#2563eb",
  primaryForeground: "#ffffff",
  positive: "#059669",
  positiveSoft: "#d1fae5",
  info: "#2563eb",
  infoSoft: "#dbeafe",
  warning: "#d97706",
  warningSoft: "#fef3c7",
  danger: "#dc2626",
  neutral: "#475569",
  neutralSoft: "#f1f5f9",
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
};

export const radius = {
  sm: 8,
  md: 12,
  lg: 16,
};

export const statusColor: Record<string, { bg: string; fg: string }> = {
  PRESENT: { bg: colors.positiveSoft, fg: colors.positive },
  CHECKED_OUT: { bg: colors.positiveSoft, fg: colors.positive },
  WFH: { bg: colors.infoSoft, fg: colors.info },
  HOLIDAY: { bg: colors.neutralSoft, fg: colors.neutral },
  LEAVE: { bg: colors.neutralSoft, fg: colors.neutral },
  ABSENT: { bg: colors.warningSoft, fg: colors.warning },
  MANUAL_OVERRIDE: { bg: colors.infoSoft, fg: colors.info },
};
