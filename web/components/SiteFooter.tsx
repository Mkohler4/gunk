export default function SiteFooter() {
  return (
    <footer>
      <div className="wrap">
        <div className="foot">
          <span className="fmark">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.7"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <path d="M4 7h16" />
              <path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7" />
              <path d="M6 7l1 12.2A1.8 1.8 0 0 0 8.8 21h6.4a1.8 1.8 0 0 0 1.8-1.8L18 7" />
            </svg>
            gunk
          </span>
          <span className="pub">
            <span className="dot" /> Building in public
          </span>
          <span className="sep">·</span>
          <span>MIT</span>
          <span className="spacer" />
          <a href="https://github.com" target="_blank" rel="noopener noreferrer">
            GitHub ↗
          </a>
        </div>
      </div>
    </footer>
  );
}
