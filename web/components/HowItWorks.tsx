export default function HowItWorks() {
  return (
    <section className="how">
      <div className="wrap">
        <p className="eyebrow reveal">
          <b>02</b> &nbsp;How it works
        </p>
        <div className="steps">
          <div className="step reveal">
            <div className="num">1</div>
            <div>
              <h3>Drop the folders</h3>
              <p>
                Drag dead project folders onto <code>gunk.app</code> in your
                menubar. Zero commands, no Full Disk Access.
              </p>
            </div>
          </div>
          <div className="step reveal">
            <div className="num">2</div>
            <div>
              <h3>gunk modularizes &amp; exposes</h3>
              <p>
                It breaks each project into reusable modules and serves them to
                your tools over <code>MCP</code> — all of it local-first.
              </p>
            </div>
          </div>
          <div className="step reveal">
            <div className="num">3</div>
            <div>
              <h3>Your AI references real code</h3>
              <p>
                Next time you ask for something, your assistant pulls your
                actual implementation instead of inventing a new one.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
