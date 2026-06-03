const X_ICON = (
  <span className="x">
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
    >
      <path d="M6 6l12 12M18 6 6 18" />
    </svg>
  </span>
);

const ITEMS: { head: string; tail: string }[] = [
  {
    head: "You ship a throwaway repo most weeks.",
    tail: "They pile up in a folder you never open again.",
  },
  {
    head: "Half of them rebuild the same thing.",
    tail: "The same auth flow, the same Stripe wrapper, the same dashboard.",
  },
  {
    head: "Your seven AI tools don't share a memory.",
    tail: "Cursor, Claude Code, Codex and OpenCode each start cold.",
  },
  {
    head: "So every “build me X” starts from zero.",
    tail: "Burning tokens to regenerate code you already wrote.",
  },
];

export default function Problem() {
  return (
    <section className="problem">
      <div className="wrap">
        <p className="eyebrow reveal">
          <b>01</b> &nbsp;The waste
        </p>
        <ul>
          {ITEMS.map((item) => (
            <li className="reveal" key={item.head}>
              {X_ICON}
              <p>
                {item.head} <span>{item.tail}</span>
              </p>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
