// Theme state (Noir-Deco dark default / daylight-noir light).
//
// The *first* application of the theme to <html data-theme> happens in a
// tiny blocking inline script in index.html, before this module (or any of
// main.ts) ever runs — that's what avoids a flash of the wrong theme on
// load. This module owns the reactive state + persistence for everything
// after that: the ThemeToggle component reads `theme.current` and calls
// `theme.set()`/`theme.toggle()`.
//
// Persistence key: localStorage['awiwi.theme'] ('dark' | 'light', default
// 'dark'). Note this differs from the T22 mockups' demo key
// ('awiwi-theme') — mockup.js is throwaway demo script, not a contract.

export type Theme = "dark" | "light";

const THEME_KEY = "awiwi.theme";
const TRANSITION_MS = 350;

function readStored(): Theme {
  try {
    return localStorage.getItem(THEME_KEY) === "light" ? "light" : "dark";
  } catch {
    return "dark";
  }
}

function readInitial(): Theme {
  if (typeof document === "undefined") return readStored();
  const attr = document.documentElement.getAttribute("data-theme");
  return attr === "light" || attr === "dark" ? attr : readStored();
}

class ThemeStore {
  current = $state<Theme>(readInitial());

  set(next: Theme): void {
    this.current = next;
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch {
      // localStorage unavailable (private mode/disabled) — theme still
      // applies for this session, just doesn't persist across reloads.
    }
    if (typeof document === "undefined") return;
    const root = document.documentElement;
    root.classList.add("theme-transition");
    root.setAttribute("data-theme", next);
    window.setTimeout(() => root.classList.remove("theme-transition"), TRANSITION_MS);
  }

  toggle(): void {
    this.set(this.current === "dark" ? "light" : "dark");
  }
}

export const theme = new ThemeStore();
