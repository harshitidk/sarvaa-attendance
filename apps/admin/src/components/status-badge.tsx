import { Badge } from "@/components/ui/badge";
import { STATUS_LABELS, STATUS_TONE, type AttendanceStatus } from "@geo/shared";

export function StatusBadge({ status }: { status: AttendanceStatus }) {
  return <Badge tone={STATUS_TONE[status]}>{STATUS_LABELS[status]}</Badge>;
}
