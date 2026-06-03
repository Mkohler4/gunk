"use client";

import { useEffect } from "react";

/**
 * Gentle reveal-on-scroll (progressive enhancement). Content is visible by
 * default; below-the-fold `.reveal` elements are "armed" (hidden) and animated
 * in via IntersectionObserver. The guaranteed-visible end state is the unarmed
 * base rule, so content can never get stuck hidden. Renders nothing.
 */
export default function ScrollReveal() {
  useEffect(() => {
    const els = Array.prototype.slice.call(
      document.querySelectorAll(".reveal"),
    ) as HTMLElement[];
    const reduce =
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    const disarmAll = () =>
      els.forEach((e) => e.classList.remove("armed"));

    if (reduce || !("IntersectionObserver" in window)) return; // already visible

    const vh = window.innerHeight || 800;
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((en) => {
          if (en.isIntersecting) {
            const el = en.target as HTMLElement;
            el.classList.add("in");
            io.unobserve(el);
            window.setTimeout(() => el.classList.remove("armed"), 900);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 },
    );

    els.forEach((el, i) => {
      const r = el.getBoundingClientRect();
      if (r.top >= vh * 0.96) {
        // below the fold → arm + observe
        el.classList.add("armed");
        el.style.transitionDelay = `${Math.min(i % 5, 4) * 45}ms`;
        io.observe(el);
      }
      // above the fold → leave visible as-is
    });

    // Safety net: if transitions don't run, disarming returns everything
    // to the visible base state instantly.
    const t = window.setTimeout(disarmAll, 1600);

    return () => {
      io.disconnect();
      window.clearTimeout(t);
    };
  }, []);

  return null;
}
