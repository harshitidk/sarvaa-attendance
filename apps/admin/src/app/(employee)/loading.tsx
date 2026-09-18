export default function EmployeeLoading() {
  return (
    <div className="animate-pulse space-y-4">
      <div className="h-7 w-32 rounded bg-muted" />
      <div className="h-48 rounded-lg bg-muted" />
      <div className="grid grid-cols-3 gap-2">
        <div className="h-16 rounded-lg bg-muted" />
        <div className="h-16 rounded-lg bg-muted" />
        <div className="h-16 rounded-lg bg-muted" />
      </div>
      <div className="h-32 rounded-lg bg-muted" />
    </div>
  );
}
