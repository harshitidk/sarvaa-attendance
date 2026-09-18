"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  CalendarDays,
  FileDown,
  History,
  LayoutDashboard,
  LogOut,
  MapPin,
  Settings,
  ShieldCheck,
  Users,
  Wrench,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { createClient } from "@/lib/supabase/client";

const NAV = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/attendance", label: "Attendance", icon: CalendarDays },
  { href: "/employees", label: "Employees", icon: Users },
  { href: "/geofences", label: "Geofences", icon: MapPin },
  { href: "/calendar", label: "Holidays & WFH", icon: CalendarDays },
  { href: "/corrections", label: "Corrections", icon: Wrench },
  { href: "/audit", label: "Audit log", icon: ShieldCheck },
  { href: "/exports", label: "Exports", icon: FileDown },
  { href: "/settings", label: "Settings", icon: Settings },
];

export function Sidebar({ name, email }: { name: string; email: string }) {
  const pathname = usePathname();
  const router = useRouter();

  async function signOut() {
    await createClient().auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <aside className="flex w-64 shrink-0 flex-col border-r bg-card">
      <div className="flex h-16 items-center gap-2 border-b px-5">
        <History className="h-5 w-5 text-primary" />
        <span className="font-semibold">Attendance Admin</span>
      </div>

      <nav className="flex-1 space-y-1 p-3">
        {NAV.map(({ href, label, icon: Icon }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                active
                  ? "bg-primary/10 text-primary"
                  : "text-muted-foreground hover:bg-accent hover:text-foreground",
              )}
            >
              <Icon className="h-4 w-4" />
              {label}
            </Link>
          );
        })}
      </nav>

      <div className="border-t p-3">
        <div className="px-2 pb-2">
          <p className="truncate text-sm font-medium">{name}</p>
          <p className="truncate text-xs text-muted-foreground">{email}</p>
        </div>
        <button
          onClick={signOut}
          className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
        >
          <LogOut className="h-4 w-4" />
          Sign out
        </button>
      </div>
    </aside>
  );
}
