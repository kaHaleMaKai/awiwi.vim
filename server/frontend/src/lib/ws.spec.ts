import { describe, it, expect } from "vitest";
import {
  backoffDelay,
  statusForFailures,
  shouldRenderIncoming,
  DOWN_AFTER_ATTEMPTS,
} from "./ws.svelte";

describe("backoffDelay", () => {
  it("follows base * factor^attempt with no jitter (random pinned to 0.5)", () => {
    const opts = { random: () => 0.5 };
    expect(backoffDelay(0, opts)).toBe(500);
    expect(backoffDelay(1, opts)).toBe(1000);
    expect(backoffDelay(2, opts)).toBe(2000);
    expect(backoffDelay(3, opts)).toBe(4000);
    expect(backoffDelay(4, opts)).toBe(8000);
  });

  it("caps at maxMs regardless of attempt", () => {
    const opts = { random: () => 0.5 };
    expect(backoffDelay(5, opts)).toBe(15_000);
    expect(backoffDelay(20, opts)).toBe(15_000);
  });

  it("never goes negative even at the jitter floor", () => {
    const delay = backoffDelay(0, { random: () => 0, jitterRatio: 1 });
    expect(delay).toBeGreaterThanOrEqual(0);
  });

  it("jitter stays within +/- jitterRatio of the raw delay", () => {
    const raw = 500;
    const jitterRatio = 0.3;
    const max = backoffDelay(0, { random: () => 1, jitterRatio });
    const min = backoffDelay(0, { random: () => 0, jitterRatio });
    expect(max).toBeLessThanOrEqual(Math.round(raw * (1 + jitterRatio)));
    expect(min).toBeGreaterThanOrEqual(Math.round(raw * (1 - jitterRatio)));
  });

  it("treats a negative attempt like attempt 0", () => {
    expect(backoffDelay(-1, { random: () => 0.5 })).toBe(backoffDelay(0, { random: () => 0.5 }));
  });

  it("respects custom baseMs/factor/maxMs", () => {
    expect(backoffDelay(0, { baseMs: 100, random: () => 0.5 })).toBe(100);
    expect(backoffDelay(1, { baseMs: 100, factor: 3, random: () => 0.5 })).toBe(300);
    expect(backoffDelay(10, { baseMs: 100, maxMs: 1000, random: () => 0.5 })).toBe(1000);
  });
});

describe("statusForFailures", () => {
  it("reports live at zero failures", () => {
    expect(statusForFailures(0)).toBe("live");
  });

  it("reports reconnecting below the down threshold", () => {
    expect(statusForFailures(1)).toBe("reconnecting");
    expect(statusForFailures(DOWN_AFTER_ATTEMPTS)).toBe("reconnecting");
  });

  it("reports down once failures exceed the threshold", () => {
    expect(statusForFailures(DOWN_AFTER_ATTEMPTS + 1)).toBe("down");
    expect(statusForFailures(100)).toBe("down");
  });
});

describe("shouldRenderIncoming", () => {
  it("renders when nothing has been seen yet", () => {
    expect(shouldRenderIncoming(null, 123)).toBe(true);
  });

  it("skips a re-render when the mtime_ns is unchanged (our own echoed write)", () => {
    expect(shouldRenderIncoming(123, 123)).toBe(false);
  });

  it("renders when the mtime_ns genuinely changed", () => {
    expect(shouldRenderIncoming(123, 456)).toBe(true);
  });

  it("handles nanosecond-scale values consistently", () => {
    const t = 1_752_480_000_123_456_789;
    expect(shouldRenderIncoming(t, t)).toBe(false);
    expect(shouldRenderIncoming(t, t + 1_000_000)).toBe(true);
  });
});
