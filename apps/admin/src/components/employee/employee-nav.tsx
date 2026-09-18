"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { CalendarDays, ChevronDown, LayoutDashboard, MapPin, Settings } from "lucide-react";
import { cn } from "@/lib/utils";
import { SignOutButton } from "@/components/sign-out-button";

const LINKS = [
  { href: "/employee", label: "Today", icon: MapPin },
  { href: "/employee/history", label: "History", icon: CalendarDays },
  { href: "/employee/settings", label: "Settings", icon: Settings },
];

function haptic() {
  if (typeof navigator !== "undefined" && "vibrate" in navigator) {
    try {
      navigator.vibrate(8);
    } catch {
      // ignore
    }
  }
}

export function EmployeeNav({ name, isAdmin }: { name: string; isAdmin: boolean }) {
  const pathname = usePathname();
  const [hidden, setHidden] = useState(false);
  const [collapsed, setCollapsed] = useState(false);

  // Auto-hide the chrome while scrolling down, reveal on scroll up (native pattern).
  useEffect(() => {
    let lastY = window.scrollY;
    let ticking = false;
    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        const y = window.scrollY;
        if (Math.abs(y - lastY) > 6) {
          setHidden(y > lastY && y > 72);
          lastY = y;
        }
        ticking = false;
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <>
      <header
        className={cn(
          "safe-top sticky top-0 z-20 border-b border-border/70 bg-card/85 backdrop-blur-xl transition-transform duration-300",
          hidden && "-translate-y-full",
        )}
      >
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-2 px-3 py-2.5">
          <div className="flex items-center gap-2">
            <span className="flex h-7 w-7 items-center justify-center rounded-[9px] bg-primary">
              <MapPin className="h-4 w-4 text-primary-foreground" />
            </span>
            <span className="text-[15px] font-semibold tracking-tight">Attendance</span>
          </div>

          <nav className="hidden items-center gap-1 sm:flex">
            {LINKS.map(({ href, label, icon: Icon }) => {
              const active = pathname === href;
              return (
                <Link
                  key={href}
                  href={href}
                  className={cn(
                    "flex items-center gap-2 rounded-full px-3 py-1.5 text-sm font-medium transition-colors",
                    active ? "bg-primary/10 text-primary" : "text-muted-foreground hover:bg-accent",
                  )}
                >
                  <Icon className="h-4 w-4" />
                  {label}
                </Link>
              );
            })}
            {isAdmin ? (
              <Link
                href="/dashboard"
                className="flex items-center gap-2 rounded-full px-3 py-1.5 text-sm font-medium text-muted-foreground hover:bg-accent"
              >
                <LayoutDashboard className="h-4 w-4" />
                Admin
              </Link>
            ) : null}
          </nav>

          <div className="flex items-center gap-1">
            {isAdmin ? (
              <Link
                href="/dashboard"
                aria-label="Admin dashboard"
                className="native-tab flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground hover:bg-accent sm:hidden"
              >
                <LayoutDashboard className="h-[18px] w-[18px]" />
              </Link>
            ) : null}
            <SignOutButton size="icon" className="native-tab h-9 w-9 rounded-full" />
          </div>
        </div>
      </header>

      <nav
        className={cn(
          "native-tabbar fixed inset-x-0 bottom-0 z-30 border-t border-border/70 bg-card/90 backdrop-blur-xl transition-transform duration-300 sm:hidden",
          hidden && "translate-y-full",
        )}
      >
        <button
          type="button"
          onClick={() => {
            haptic();
            setCollapsed((c) => !c);
          }}
          aria-label={collapsed ? "Expand navigation" : "Collapse navigation"}
          className="absolute -top-3 left-1/2 flex h-6 w-12 -translate-x-1/2 items-center justify-center rounded-full border border-border/70 bg-card shadow-sm"
        >
          <ChevronDown
            className={cn("h-4 w-4 text-muted-foreground transition-transform duration-300", collapsed && "rotate-180")}
          />
        </button>

        <div className="mx-auto flex max-w-3xl items-stretch">
          {LINKS.map(({ href, label, icon: Icon }) => {
            const active = pathname === href;
            return (
              <Link
                key={href}
                href={href}
                onClick={haptic}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "native-tab flex flex-1 flex-col items-center justify-center gap-0.5 transition-[padding] duration-300",
                  collapsed ? "py-2" : "pb-1.5 pt-2",
                )}
              >
                <span
                  className={cn(
                    "flex h-7 w-14 items-center justify-center rounded-full transition-colors duration-200",
                    active ? "bg-primary/12 text-primary" : "text-muted-foreground",
                  )}
                >
                  <Icon className="h-5 w-5" strokeWidth={active ? 2.4 : 2} />
                </span>
                <span
                  className={cn(
                    "text-[10px] font-medium leading-none transition-all duration-200",
                    active ? "text-primary" : "text-muted-foreground",
                    collapsed && "hidden",
                  )}
                >
                  {label}
                </span>
              </Link>
            );
          })}
        </div>
      </nav>
    </>
  );
}
