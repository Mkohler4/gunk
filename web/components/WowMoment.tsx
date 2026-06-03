export default function WowMoment() {
  return (
    <section className="wow">
      <div className="wrap">
        <p className="eyebrow reveal">
          <b>03</b> &nbsp;The difference
        </p>
        <h2 className="reveal">Same prompt. Your code instead of new code.</h2>
        <p className="sub reveal">
          Ask for Google OAuth you&rsquo;ve already written four times — and
          watch what changes.
        </p>

        <div className="compare">
          <div className="card reveal">
            <span className="tag">
              <span className="pip" /> Without gunk
            </span>
            <div className="prompt">
              <span className="you">you ›</span> build me Google OAuth
            </div>
            <p className="reply dim">
              Generates brand-new code — subtly different from the four other
              auth flows already sitting in your repos.
            </p>
            <div className="meta">
              <span>
                ~<b>4,000</b> tokens
              </span>
              <span>
                <b>30s</b>
              </span>
            </div>
          </div>

          <div className="card good reveal">
            <span className="tag">
              <span className="pip" /> With gunk
            </span>
            <div className="prompt">
              <span className="you">you ›</span> build me Google OAuth
            </div>
            <p className="reply">
              “I see you have an auth module in{" "}
              <span className="path">proj-47/lib/auth/</span>. Use that
              pattern?”
            </p>
            <div className="meta">
              <span>
                ~<b>200</b> tokens
              </span>
              <span>
                <b>3s</b>
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
