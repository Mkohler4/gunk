"use client";

import { useRef, useState } from "react";

/**
 * Placeholder signup form. To actually collect addresses, point `action` at a
 * real endpoint (Buttondown, ConvertKit, your own /subscribe) and drop the
 * preventDefault in `onSubmit`.
 */
export default function SignupForm() {
  const [submittedEmail, setSubmittedEmail] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const input = inputRef.current;
    if (!input || !input.value || !input.checkValidity()) {
      input?.focus();
      return;
    }
    setSubmittedEmail(input.value);
    e.currentTarget.reset();
  };

  return (
    <>
      <form className="signup reveal" action="#" method="post" noValidate onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="email" className="visually-hidden">
            Email address
          </label>
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            placeholder="you@machine.local"
            ref={inputRef}
          />
        </div>
        <button className="btn" type="submit">
          Get notified
        </button>
      </form>
      <p className="formnote reveal" id="formnote">
        {submittedEmail ? (
          <span className="formok">
            ✓ You&rsquo;re on the list — we&rsquo;ll email {submittedEmail} when
            gunk opens up.
          </span>
        ) : (
          <>
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <rect x="4" y="10.5" width="16" height="10" rx="2" />
              <path d="M8 10.5V7a4 4 0 0 1 8 0v3.5" />
            </svg>
            No download yet. One email when gunk opens up — nothing else.
          </>
        )}
      </p>
    </>
  );
}
