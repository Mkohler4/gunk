import SignupForm from "./SignupForm";

export default function Hero() {
  return (
    <section className="hero">
      <div className="wrap hero-grid">
        <div className="hero-copy">
          <span className="badge reveal">
            <span className="dot" /> Pre-launch · building in public
          </span>
          <h1 className="reveal">
            Reinventing
            <br />
            the trash can.
          </h1>
          <p className="lede reveal">
            gunk turns your <b>dead side projects</b> into context your AI
            actually uses.
          </p>

          <SignupForm />
        </div>

        <div
          className="hero-art reveal"
          tabIndex={0}
          role="img"
          aria-label="gunk, a smart trash can"
        >
          <svg
            className="bigbin"
            viewBox="0 0 24 24"
            fill="none"
            strokeWidth="1.25"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
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
        </div>
      </div>
    </section>
  );
}
