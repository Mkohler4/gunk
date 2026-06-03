"use client";

import { useEffect, useRef } from "react";

/**
 * One-time intro: the trash can opens, the word "gunk" appears, then the
 * overlay zooms through to reveal the page. Whether it plays at all is decided
 * before paint by the inline script in layout.tsx (sets html[data-intro]).
 *
 * The overlay always renders; visibility is driven entirely by html[data-intro]
 * (see globals.css): "play" shows + locks scroll, "skip" hides + unlocks. We
 * never unmount via state, which keeps SSR markup stable and avoids
 * setState-in-effect cascades.
 */
export default function Intro() {
  const introRef = useRef<HTMLDivElement>(null);
  const endRef = useRef<() => void>(() => {});

  useEffect(() => {
    const root = document.documentElement;
    const intro = introRef.current;
    if (!intro) return;

    // The pre-paint script already decided. "skip" => CSS keeps it hidden.
    if (root.getAttribute("data-intro") !== "play") return;

    try {
      sessionStorage.setItem("gunk-intro", "1");
    } catch {
      /* ignore */
    }

    let ended = false;
    const finish = () => {
      if (ended) return;
      ended = true;

      const done = () => root.setAttribute("data-intro", "skip"); // hide + unlock

      const introBin = intro.querySelector<HTMLElement>(".intro-bin");
      const heroBin = document.querySelector<HTMLElement>(".bigbin");

      // Shared-element handoff: fly the intro bin into the hero bin's exact
      // slot, dissolve the backdrop to reveal the page, then swap to the real
      // (identical) hero bin so it reads as one continuous object.
      try {
        if (introBin && heroBin) {
          const word = intro.querySelector<HTMLElement>(".intro-word");
          const bg = intro.querySelector<HTMLElement>(".intro-bg");
          const lid = introBin.querySelector<HTMLElement>(".bin-lid");

          // Hide the real bin (keeps its layout box) so we never show two bins.
          heroBin.style.visibility = "hidden";

          // Freeze the intro bin to its settled state and drop the keyframe
          // animations so our transform can take over without the fill fighting it.
          introBin.style.animation = "none";
          introBin.style.opacity = "1";
          introBin.style.transform = "none";
          if (lid) {
            lid.style.animation = "none";
            lid.style.transform = "none";
          }
          if (word) {
            word.style.animation = "none";
            word.style.opacity = "1";
            word.style.transform = "none";
          }
          void intro.offsetWidth; // commit the frozen start state

          const from = introBin.getBoundingClientRect();
          const to = heroBin.getBoundingClientRect();
          const scale = to.width / from.width;
          const dx = to.left + to.width / 2 - (from.left + from.width / 2);
          const dy = to.top + to.height / 2 - (from.top + from.height / 2);

          requestAnimationFrame(() => {
            introBin.style.transition =
              "transform .85s cubic-bezier(.65,0,.2,1)";
            introBin.style.transform = `translate(${dx}px, ${dy}px) scale(${scale})`;
            if (word) {
              word.style.transition = "opacity .25s ease";
              word.style.opacity = "0";
            }
            if (bg) {
              bg.style.transition = "opacity .6s ease .12s";
              bg.style.opacity = "0";
            }
          });

          window.setTimeout(() => {
            heroBin.style.visibility = "";
            done();
          }, 880);
          return;
        }
      } catch {
        heroBin?.style.setProperty("visibility", "");
        done();
        return;
      }

      // Fallback if the hero bin isn't found or the handoff cannot run.
      intro.classList.add("leaving");
      window.setTimeout(() => {
        try {
          done();
        } catch {
          root.setAttribute("data-intro", "skip");
        }
      }, 820);
    };
    endRef.current = finish;

    // Kick off the animation on the next frames.
    const raf = requestAnimationFrame(() =>
      requestAnimationFrame(() => intro.classList.add("play")),
    );

    const timer = window.setTimeout(finish, 2450);
    const onClick = (e: MouseEvent) => {
      if (e.target === intro) finish();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" || e.key === "Enter" || e.key === " ") finish();
    };
    intro.addEventListener("click", onClick);
    document.addEventListener("keydown", onKey);

    // Watchdog: never trap the page if something stalls.
    const watchdog = window.setTimeout(() => {
      if (!ended) finish();
    }, 4000);

    return () => {
      cancelAnimationFrame(raf);
      window.clearTimeout(timer);
      window.clearTimeout(watchdog);
      intro.removeEventListener("click", onClick);
      document.removeEventListener("keydown", onKey);
    };
  }, []);

  return (
    <div className="intro" id="intro" role="presentation" ref={introRef}>
      <div className="intro-bg" aria-hidden="true" />
      <div className="intro-stage">
        <svg
          className="intro-bin"
          viewBox="0 0 24 24"
          fill="none"
          strokeWidth="1.3"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <circle className="mote a" cx="9.4" cy="5" r="0.7" stroke="none" />
          <circle className="mote b" cx="12" cy="5" r="0.7" stroke="none" />
          <circle className="mote c" cx="14.6" cy="5" r="0.7" stroke="none" />
          <g className="bin-body">
            <path d="M6 7l1 12.2A1.8 1.8 0 0 0 8.8 21h6.4a1.8 1.8 0 0 0 1.8-1.8L18 7" />
          </g>
          <g className="bin-ribs">
            <path d="M10 11l1 6M14 11l-1 6" />
          </g>
          <g className="bin-lid">
            <path d="M4 7h16" />
            <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
          </g>
        </svg>
        <div className="intro-word">gunk</div>
      </div>
      <button
        className="intro-skip"
        type="button"
        onClick={() => endRef.current()}
      >
        Skip
      </button>
    </div>
  );
}
